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
	Eligible   int    `json:"up_nonloopback_interfaces"`
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "benchmark" {
		benchmark(os.Args[2:])
		return
	}
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
	step, cleanup := prepare(*scenario, *duration)
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

func prepare(scenario string, duration time.Duration) (func(), func()) {
	switch scenario {
	case "interfaces":
		return func() { _, err := net.Interfaces(); check(err) }, func() {}
	case "addresses":
		return enumerateAddresses, func() {}
	case "mesh-query", "idle-lan", "idle-no-lan":
		cfg := mesh.DefaultOfflineConfig()
		cfg.NetworkID = "mosh-isolated-interface-profile/1"
		cfg.LANDiscoveryEnabled = scenario == "idle-lan"
		cfg.LANDiscoveryPort = 44446
		node, err := mesh.NewNode("profile", nil, cfg)
		check(err)
		if scenario == "mesh-query" {
			var info struct {
				AdvertisedAddr string `json:"advertised_addr"`
			}
			check(json.Unmarshal([]byte(node.MeshInfoJSON()), &info))
			if info.AdvertisedAddr == "" {
				panic("empty advertised address")
			}
			return func() { _ = node.MeshInfoJSON() }, func() {}
		}
		if status := node.Start(); status != mesh.MOSS_OK {
			panic(fmt.Sprintf("node start: %d", status))
		}
		time.Sleep(time.Second)
		return func() { time.Sleep(duration) }, func() { node.Stop() }
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
