// Standalone attribution probe; imports the pinned, unchanged Moss module.
package main

import (
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

type result struct {
	Scenario   string `json:"scenario"`
	Iterations int    `json:"iterations"`
	ElapsedNS  int64  `json:"elapsed_ns"`
	GoVersion  string `json:"go_version"`
	Interfaces int    `json:"interfaces"`
	Eligible   int    `json:"eligible_interfaces"`
}

func main() {
	scenario := flag.String("scenario", "mesh-query", "mesh-query, interfaces, addresses, idle-lan, idle-no-lan")
	duration := flag.Duration("duration", 15*time.Second, "profile interval")
	output := flag.String("output", "probe", "output prefix")
	flag.Parse()
	if *duration <= 0 {
		panic("duration must be positive")
	}
	ifaces, err := net.Interfaces()
	check(err)
	eligible := 0
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp != 0 && iface.Flags&net.FlagLoopback == 0 {
			eligible++
		}
	}
	step, cleanup := prepare(*scenario)
	defer cleanup()
	f, err := os.Create(*output + ".pprof")
	check(err)
	check(pprof.StartCPUProfile(f))
	start := time.Now()
	iterations := 0
	for time.Since(start) < *duration {
		step()
		iterations++
	}
	elapsed := time.Since(start)
	pprof.StopCPUProfile()
	check(f.Close())
	r := result{*scenario, iterations, elapsed.Nanoseconds(), runtime.Version(), len(ifaces), eligible}
	f, err = os.Create(*output + ".json")
	check(err)
	check(json.NewEncoder(f).Encode(r))
	check(f.Close())
	fmt.Printf("%s: %d iterations in %s\n", *scenario, iterations, elapsed)
}

func prepare(scenario string) (func(), func()) {
	switch scenario {
	case "interfaces":
		return func() { _, err := net.Interfaces(); check(err) }, func() {}
	case "addresses":
		return enumerateAddresses, func() {}
	case "mesh-query", "idle-lan", "idle-no-lan":
		cfg := mesh.DefaultConfig()
		cfg.NetworkID = "mosh-isolated-interface-profile/1"
		cfg.Trackers = nil
		cfg.DHTEnabled = false
		cfg.LANDiscoveryEnabled = scenario == "idle-lan"
		cfg.LANDiscoveryPort = 44446
		cfg.MasqConfig.Enabled = false
		node, err := mesh.NewNode("profile", nil, cfg)
		check(err)
		if scenario == "mesh-query" {
			return func() {
				var info map[string]any
				check(json.Unmarshal([]byte(node.MeshInfoJSON()), &info))
				if info["advertised_addr"] == "" {
					panic("empty advertised address")
				}
			}, func() {}
		}
		if status := node.Start(); status != mesh.MOSS_OK {
			panic(fmt.Sprintf("node start: %d", status))
		}
		time.Sleep(time.Second)
		return func() { time.Sleep(10 * time.Millisecond) }, func() { node.Stop() }
	default:
		panic("unknown scenario: " + scenario)
	}
}

func enumerateAddresses() {
	ifaces, err := net.Interfaces()
	check(err)
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		_, err := iface.Addrs()
		check(err)
	}
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}
