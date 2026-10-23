package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"os"
	"runtime"
	"sort"
	"time"

	mcrypto "github.com/redstone-md/moss/internal/crypto"
	"github.com/redstone-md/moss/internal/mesh"
)

type benchmarkResult struct {
	Iterations int    `json:"iterations"`
	WallNS     int64  `json:"wall_ns"`
	CPUNS      int64  `json:"cpu_ns"`
	P50NS      int64  `json:"p50_ns"`
	P95NS      int64  `json:"p95_ns"`
	P99NS      int64  `json:"p99_ns"`
	Golden     string `json:"golden"`
	GoVersion  string `json:"go_version"`
}

func benchmark(args []string) {
	flags := flag.NewFlagSet("benchmark", flag.ExitOnError)
	iterations := flags.Int("iterations", 600, "mesh API reads")
	fixture := flags.String("fixture", "", "private shared identity fixture")
	output := flags.String("output", "", "aggregate JSON result")
	check(flags.Parse(args))
	if *iterations < 1 || *fixture == "" || *output == "" {
		panic("positive iterations, fixture and output are required")
	}
	identity := benchmarkIdentity(*fixture)
	cfg := mesh.DefaultOfflineConfig()
	cfg.NetworkID = "mosh-isolated-interface-benchmark/1"
	node, err := mesh.NewNodeWithIdentity("benchmark", nil, cfg, identity)
	check(err)
	want := sha256.Sum256([]byte(node.MeshInfoJSON()))
	for i := 0; i < 20; i++ {
		if sha256.Sum256([]byte(node.MeshInfoJSON())) != want {
			panic("unstable warmup output")
		}
	}
	r := measureMeshReads(node, *iterations, want)
	r.Golden, r.GoVersion = hex.EncodeToString(want[:]), runtime.Version()
	f, err := os.Create(*output)
	check(err)
	check(json.NewEncoder(f).Encode(r))
	check(f.Close())
}

func benchmarkIdentity(path string) *mcrypto.Identity {
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		identity, err := mcrypto.NewIdentity()
		check(err)
		check(os.WriteFile(path, identity.Encode(), 0600))
		return identity
	}
	check(err)
	identity, err := mcrypto.DecodeIdentity(raw)
	check(err)
	return identity
}

func measureMeshReads(node *mesh.Node, iterations int, want [32]byte) benchmarkResult {
	latencies := make([]int64, iterations)
	cpu := processCPU()
	start := time.Now()
	for i := range latencies {
		step := time.Now()
		if sha256.Sum256([]byte(node.MeshInfoJSON())) != want {
			panic("mesh output differs during benchmark")
		}
		latencies[i] = time.Since(step).Nanoseconds()
	}
	r := benchmarkResult{Iterations: iterations, WallNS: time.Since(start).Nanoseconds(), CPUNS: processCPU() - cpu}
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	r.P50NS = latencies[(iterations-1)*50/100]
	r.P95NS = latencies[(iterations-1)*95/100]
	r.P99NS = latencies[(iterations-1)*99/100]
	return r
}
