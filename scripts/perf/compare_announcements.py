"""Matched, offline signature-component comparison; publishes no app identities."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys


def main():
    root = Path(sys.argv[1]).resolve()
    results = {name: [] for name in ("before", "after")}
    golden = None
    for variant in results:
        output = subprocess.check_output([
            str(root / f"{variant}.exe"), "-test.run=^TestAnnouncementVerificationHandlerGolden$",
            "-test.v", "-test.count=1",
        ], text=True)
        digest = re.search(r"GOLDEN ([0-9a-f]{64})", output)[1]
        golden = digest if golden is None else golden
        assert digest == golden, "handler state changed"
    for pair in range(20):
        order = ("before", "after") if pair % 2 == 0 else ("after", "before")
        for variant in order:
            output = subprocess.check_output([
                str(root / f"{variant}.exe"), "-test.run=^$", "-test.cpu=1",
                "-test.bench=^BenchmarkAnnouncementVerification$", "-test.benchtime=8x",
            ], text=True)
            rows = re.findall(
                r"BenchmarkAnnouncementVerification/(repeated|unique|invalid)\s+8\s+([\d.]+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op",
                output,
            )
            assert len(rows) == 3, output
            data = {mode: {"ns_per_check": float(ns) / 2048,
                           "bytes_per_check": int(size) / 2048,
                           "allocs_per_check": int(allocs) / 2048}
                    for mode, ns, size, allocs in rows}
            results[variant].append(data)
    summary = {"pairs": 20, "checks_per_mode_per_sample": 16384,
               "repeated_share_per_batch": 0.875, "handler_golden": golden,
               "binaries": {name: hashlib.sha256((root / f"{name}.exe").read_bytes()).hexdigest()
                            for name in results},
               "median_ns_per_check": {name: {mode: statistics.median(
                   row[mode]["ns_per_check"] for row in rows)
                   for mode in ("repeated", "unique", "invalid")}
                   for name, rows in results.items()}}
    summary["change_pct"] = {mode: 100 * (summary["median_ns_per_check"]["after"][mode] /
                                          summary["median_ns_per_check"]["before"][mode] - 1)
                             for mode in ("repeated", "unique", "invalid")}
    summary["repeated_improved_pairs"] = sum(
        after["repeated"]["ns_per_check"] < before["repeated"]["ns_per_check"]
        for before, after in zip(results["before"], results["after"]))
    (root / "comparison.json").write_text(json.dumps(summary, indent=2))
    (root / "samples.json").write_text(json.dumps(results, indent=2))
    print(json.dumps(summary, indent=2))
    assert summary["change_pct"]["repeated"] < 0, "no repeated-work improvement"


if __name__ == "__main__":
    main()
