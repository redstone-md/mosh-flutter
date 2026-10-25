"""Paired, optimized direct-readiness waits; no public network or user store."""

import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time


def parse_metrics(output):
    rows = [line.split() for line in output.splitlines()
            if line.startswith('BenchmarkDirectPeerWaitOffline-')]
    if len(rows) != 1 or rows[0][1] != '5':
        raise ValueError('Expected one five-batch benchmark row')
    row = rows[0]
    if (len(row) - 2) % 2:
        raise ValueError('Unpaired benchmark metric')
    metrics = {row[i + 1]: float(row[i]) for i in range(2, len(row), 2)}
    required = {'ns/op', 'cpu-ns/batch', 'false-results/batch', 'B/op', 'allocs/op'}
    if set(metrics) != required or not all(math.isfinite(v) and v >= 0 for v in metrics.values()):
        raise ValueError('Invalid benchmark metrics')
    if metrics['false-results/batch'] != 8 or not 0.9e9 <= metrics['ns/op'] < 2e9:
        raise ValueError('Offline outcomes or wait duration changed')
    return metrics


def run(root, variant, label):
    started = time.perf_counter()
    result = subprocess.run([
        str((root / (variant + '.exe')).resolve()), '-test.run=^$',
        '-test.bench=^BenchmarkDirectPeerWaitOffline$', '-test.benchtime=5x',
        '-test.cpu=4', '-test.benchmem', '-test.timeout=60s',
    ], capture_output=True, text=True, check=True, timeout=75,
        env={**os.environ, 'GOMAXPROCS': '4'})
    (root / (label + '-' + variant + '.txt')).write_text(result.stdout)
    return dict(variant=variant, elapsed_s=time.perf_counter() - started,
                metrics=parse_metrics(result.stdout))


def stats(values):
    ordered = sorted(values)
    return dict(min=min(values), median=statistics.median(values),
                p95=ordered[math.ceil(len(values) * 0.95) - 1], max=max(values))


def main(root):
    root = Path(root)
    fingerprint = json.loads((root / 'fingerprint.json').read_text(encoding='utf-8-sig'))
    for variant in ('before', 'after'):
        actual = hashlib.sha256((root / (variant + '.exe')).read_bytes()).hexdigest()
        if actual != fingerprint[variant + '_exe_sha256']:
            raise ValueError('Executable fingerprint mismatch')
        run(root, variant, 'warmup')
    pairs = []
    for index in range(20):
        order = ('before', 'after') if index % 2 == 0 else ('after', 'before')
        records = [run(root, variant, f'pair-{index:02}') for variant in order]
        pairs.append(dict(index=index, order=order, records=records))
        (root / 'pairs.json').write_text(json.dumps(pairs, indent=2))
        print(f'Completed pair {index + 1}/20', flush=True)
    summaries = {}
    metric_names = ('ns/op', 'cpu-ns/batch', 'B/op', 'allocs/op')
    for variant in ('before', 'after'):
        records = [r for p in pairs for r in p['records'] if r['variant'] == variant]
        summaries[variant] = {key: stats([r['metrics'][key] for r in records])
                              for key in metric_names}
    differences = {}
    for key in metric_names:
        deltas = []
        for pair in pairs:
            values = {r['variant']: r['metrics'][key] for r in pair['records']}
            deltas.append(values['after'] - values['before'])
        differences[key] = dict(**stats(deltas), improved_pairs=sum(d < 0 for d in deltas),
                                unchanged_pairs=sum(d == 0 for d in deltas))
    result = dict(fingerprint=fingerprint, scenario='eight absent peers, one-second waits',
                  pairs=20, batches_per_process=5, waiters_per_batch=8,
                  expected_false_results=1600,
                  outcomes_sha256=hashlib.sha256(b'false\n' * 1600).hexdigest(),
                  summaries=summaries, paired_after_minus_before=differences,
                  limits=['No public topology, FFI, Rust, Flutter or user store',
                          'Windows process CPU counters have finite resolution',
                          'Zero counter deltas do not mean zero CPU work',
                          'Native wait cost does not establish whole-Mosh gains'])
    (root / 'results.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main(sys.argv[1])
