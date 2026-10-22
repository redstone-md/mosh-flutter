"""Bounded Microsoft PerfView sampling; export target-only aggregate frames."""
import csv
import json
from pathlib import Path, PureWindowsPath
import subprocess
import sys


class CpuProfile:
    def __init__(self, tool, root, name, process, seconds=90):
        self.tool, self.process = str(tool), process
        self.root, self.name = Path(root), name
        raw = self.root / 'raw'
        raw.mkdir(exist_ok=True)
        self.trace = raw / (name + '.etl')
        self.log = (raw / (name + '.log')).open('w')
        self.child = subprocess.Popen([
            self.tool, '/AcceptEula', '/NoGui', '/Zip:false',
            '/KernelEvents:Process+Thread+ImageLoad+Profile', '/ClrEvents:None',
            '/MaxCollectSec:' + str(seconds), '/DataFile:' + str(self.trace),
            '/LogFile:' + str(raw / (name + '-perfview.log')), 'collect'],
            stdout=self.log, stderr=subprocess.STDOUT)

    def finish(self):
        try:
            if self.child.wait(timeout=180):
                raise RuntimeError('PerfView sampling failed: ' + self.name)
            subprocess.run([
                self.tool, '/AcceptEula', '/NoGui',
                '/LogFile:' + str(self.trace.with_suffix('.export.log')),
                'userCommand', 'SaveCPUStacksAsCsv', str(self.trace),
                self.process, '2147483647'],
                stdout=self.log, stderr=subprocess.STDOUT, check=True, timeout=180)
            return export(self.trace.with_suffix('.perfView.csv'),
                          self.root / (self.name + '-cpu.json'))
        finally:
            self.log.close()


def export(source, output):
    modules, frames = {}, []
    unknown = total = 0.0
    with source.open(encoding='utf-8-sig') as stream:
        for row in csv.DictReader(stream):
            cost = float(row['Exc'])
            if cost <= 0:
                continue
            total += cost
            name = row['Name']
            if '!' not in name:
                unknown += cost
                continue
            module, symbol = name.split('!', 1)
            module = PureWindowsPath(module).name
            modules[module] = modules.get(module, 0) + cost
            frames.append({'frame': module + '!' + symbol, 'sampled_ms': cost})
    if total <= 0:
        raise RuntimeError('No target CPU samples in PerfView export')
    result = {
        'sampled_ms': total, 'unresolved_ms': unknown,
        'modules': [{'module': k, 'sampled_ms': v, 'percent': 100 * v / total}
                    for k, v in sorted(modules.items(), key=lambda kv: -kv[1])],
        'frames': sorted(frames, key=lambda row: -row['sampled_ms'])[:40],
        'note': 'Sampled instruction frames, not thread start addresses. Raw system trace stays local.'}
    output.write_text(json.dumps(result, indent=2))
    return result


def control(tool, root):
    child = subprocess.Popen([sys.executable, '-c',
                              'import math,time\nend=time.monotonic()+30\n'
                              'while time.monotonic()<end: math.sqrt(12345)'])
    try:
        result = CpuProfile(tool, root, 'control', 'python', seconds=12).finish()
        assert result['sampled_ms'] >= 2000, 'Busy child CPU samples missing'
        assert any('python' in r['module'].lower() for r in result['modules']), 'Python module attribution missing'
        print('Validated real sampled CPU/module attribution', flush=True)
    finally:
        if child.poll() is None:
            child.terminate()
        child.wait(timeout=15)


if __name__ == '__main__':
    control(sys.argv[1], Path(sys.argv[2]))
