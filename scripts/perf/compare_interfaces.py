"""Alternating same-host component comparison; never exports fixture keys."""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys


def main():
    root = Path(sys.argv[1]).resolve()
    fixture = Path(os.environ["RUNNER_TEMP"]) / "interface-benchmark-private-identity"
    results = {"before": [], "after": []}
    golden = None
    for pair in range(20):
        order = ("before", "after") if pair % 2 == 0 else ("after", "before")
        for variant in order:
            output = root / f"{variant}-{pair:02}.json"
            subprocess.run([
                str(root / f"{variant}.exe"), "benchmark", "-iterations", "600",
                "-fixture", str(fixture), "-output", str(output),
            ], check=True)
            data = json.loads(output.read_text())
            assert data["iterations"] == 600 and data["cpu_ns"] > 0
            assert data["go_version"] == "go1.25.9"
            golden = data["golden"] if golden is None else golden
            assert data["golden"] == golden, "ordered API output changed"
            results[variant].append(data)
    summary = {
        "pairs": 20, "iterations_per_process": 600, "golden": golden,
        "binaries": {name: hashlib.sha256((root / f"{name}.exe").read_bytes()).hexdigest()
                     for name in results},
        "median": {name: {key: statistics.median(row[key] for row in rows)
                          for key in ("cpu_ns", "wall_ns", "p50_ns", "p95_ns", "p99_ns")}
                   for name, rows in results.items()},
        "improved_pairs": sum(a["cpu_ns"] < b["cpu_ns"]
                              for a, b in zip(results["after"], results["before"])),
    }
    summary["cpu_reduction_pct"] = 100 * (1 - summary["median"]["after"]["cpu_ns"] /
                                         summary["median"]["before"]["cpu_ns"])
    (root / "comparison.json").write_text(json.dumps(summary, indent=2))
    assert summary["cpu_reduction_pct"] > 0, "no measured CPU improvement"
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
