package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"runtime"
	"runtime/pprof"
	"time"

	"github.com/redstone-md/moss/internal/mesh"
)

// Mirrors the static overrides in mosh-core/src/moss_ffi/config.rs.
const publicMoshConfig = `{
 "announce_interval_sec":15,"bootstrap_timeout_sec":12,"explicit_retry_max_sec":30,
 "lan_discovery_enabled":true,"gossipsub":{"heartbeat_ms":250},
 "nat":{"upnp_enabled":true,"natpmp_enabled":true,"pcp_enabled":true,
 "hole_punch_attempts":8,"port_prediction_enabled":true}}`

type topology struct {
	Peers         int    `json:"peer_count"`
	Direct        int    `json:"direct_peer_count"`
	Relayed       int    `json:"relayed_peer_count"`
	Known         int    `json:"known_peer_count"`
	RelaySessions int    `json:"relay_session_count"`
	RelayRoutes   int    `json:"relay_route_count"`
	NAT           string `json:"nat_type"`
}

type memory struct {
	Allocated  uint64 `json:"heap_alloc_bytes"`
	Inuse      uint64 `json:"heap_inuse_bytes"`
	Idle       uint64 `json:"heap_idle_bytes"`
	Released   uint64 `json:"heap_released_bytes"`
	TotalAlloc uint64 `json:"total_alloc_bytes"`
	GCCount    uint32 `json:"gc_count"`
	Goroutines int    `json:"goroutines"`
}

type publicPhase struct {
	Name           string   `json:"name"`
	ElapsedNS      int64    `json:"elapsed_ns"`
	CPUNS          int64    `json:"cpu_ns"`
	Reads          int      `json:"scheduled_mesh_reads"`
	Before         topology `json:"topology_before"`
	After          topology `json:"topology_after"`
	MemoryBefore   memory   `json:"memory_before"`
	MemoryAfter    memory   `json:"memory_after"`
	GoVersion      string   `json:"go_version"`
	GOMAXPROCS     int      `json:"gomaxprocs"`
	WarmupNS       int64    `json:"warmup_requested_ns"`
	RoomCount      int      `json:"rooms_created"`
	Subscriptions  int      `json:"subscriptions_registered"`
	KnownPolicies  int      `json:"known_dm_policies"`
	Config         string   `json:"static_mosh_overrides"`
	SamplerEnabled bool     `json:"sampler_included_in_cpu_window"`
}

func publicIdle(args []string) {
	flags := flag.NewFlagSet("public-idle", flag.ExitOnError)
	warmup := flags.Duration("warmup", 480*time.Second, "public-node warmup")
	duration := flags.Duration("duration", 90*time.Second, "each profile window")
	output := flags.String("output", "public-idle", "aggregate/profile prefix")
	check(flags.Parse(args))
	if *warmup < 0 || *duration <= 0 {
		panic("invalid profile duration")
	}
	cfg, err := mesh.ParseConfig(publicMoshConfig)
	check(err)
	cfg.ListenPort = dualProtocolPort()
	node, err := mesh.NewNode("mosh-dm/1", nil, cfg)
	check(err)
	status(node.Start())
	defer node.Stop()
	registerPublicRooms(node)
	time.Sleep(*warmup)
	for _, name := range []string{"mesh-polls", "service-only"} {
		r := profilePublicPhase(node, name, *duration, *output+"-"+name)
		r.GoVersion, r.GOMAXPROCS = runtime.Version(), runtime.GOMAXPROCS(0)
		r.WarmupNS, r.RoomCount, r.Subscriptions = int64(*warmup), 11, 33
		r.KnownPolicies, r.Config, r.SamplerEnabled = 8, publicMoshConfig, true
		writeAggregate(*output+"-"+name+".json", r)
	}
}

func dualProtocolPort() int {
	for attempt := 0; attempt < 16; attempt++ {
		udp, err := net.ListenPacket("udp4", "0.0.0.0:0")
		if err != nil {
			continue
		}
		port := udp.LocalAddr().(*net.UDPAddr).Port
		tcp, err := net.Listen("tcp4", fmt.Sprintf("0.0.0.0:%d", port))
		check(udp.Close())
		if err == nil {
			check(tcp.Close())
			return port
		}
	}
	panic("no available TCP/UDP port")
}

func registerPublicRooms(node *mesh.Node) {
	for room := 0; room < 11; room++ {
		public, _, err := ed25519.GenerateKey(rand.Reader)
		check(err)
		id := hex.EncodeToString(public)
		name := "mosh-profile/" + id
		status(node.JoinRoom(name, nil))
		for _, channel := range []string{"control", "chat", "blob"} {
			status(node.SubscribeRoom(name, channel))
		}
		if room < 8 {
			status(node.ConnectToPeer(id))
			status(node.SetRoomPeerDiscovery(name, mesh.RoomDiscoveryKnownPeers, []string{id}))
		}
	}
}

func profilePublicPhase(node *mesh.Node, name string, duration time.Duration, prefix string) publicPhase {
	r := publicPhase{Name: name, Before: readTopology(node), MemoryBefore: readMemory()}
	if r.Before.Peers == 0 || r.Before.Known == 0 {
		panic("public topology not established")
	}
	f, err := os.Create(prefix + ".pprof")
	check(err)
	check(pprof.StartCPUProfile(f))
	cpu, start := processCPU(), time.Now()
	r.Reads = scheduledReads(node, duration, name == "mesh-polls")
	r.ElapsedNS, r.CPUNS = time.Since(start).Nanoseconds(), processCPU()-cpu
	pprof.StopCPUProfile()
	check(f.Close())
	r.MemoryAfter, r.After = readMemory(), readTopology(node)
	writeRuntimeProfiles(prefix)
	return r
}

func scheduledReads(node *mesh.Node, duration time.Duration, poll bool) int {
	end := time.NewTimer(duration)
	defer end.Stop()
	if !poll {
		<-end.C
		return 0
	}
	ticks := time.NewTicker(time.Second)
	defer ticks.Stop()
	reads := 0
	for {
		select {
		case <-end.C:
			return reads
		case <-ticks.C:
			for i := 0; i < 6; i++ {
				_ = node.MeshInfoJSON()
				reads++
			}
		}
	}
}

func readTopology(node *mesh.Node) topology {
	var result topology
	check(json.Unmarshal([]byte(node.MeshInfoJSON()), &result))
	return result
}

func readMemory() memory {
	var s runtime.MemStats
	runtime.ReadMemStats(&s)
	return memory{s.HeapAlloc, s.HeapInuse, s.HeapIdle, s.HeapReleased,
		s.TotalAlloc, s.NumGC, runtime.NumGoroutine()}
}

func writeRuntimeProfiles(prefix string) {
	for _, name := range []string{"heap", "allocs", "goroutine"} {
		f, err := os.Create(prefix + "-" + name + ".pprof")
		check(err)
		check(pprof.Lookup(name).WriteTo(f, 0))
		check(f.Close())
	}
}

func writeAggregate(path string, value publicPhase) {
	f, err := os.Create(path)
	check(err)
	check(json.NewEncoder(f).Encode(value))
	check(f.Close())
}

func status(code int32) {
	if code != mesh.MOSS_OK {
		panic(fmt.Sprintf("node operation returned %d", code))
	}
}
