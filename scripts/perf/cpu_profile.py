"""Exact-PID collector and sanitized caller stacks for a disposable CI fixture."""
import json
from pathlib import Path
import re
import shutil
import subprocess

from stack_export import export_stacks


def error_summary(text):
    kinds = [
        'NullReferenceException', 'InvalidOperationException', 'FileLoadException',
        'FileNotFoundException', 'DirectoryNotFoundException', 'NotSupportedException',
        'ArgumentException', 'UnauthorizedAccessException', 'BadImageFormatException',
        'TypeLoadException', 'TimeoutException', 'TargetInvocationException',
    ]
    methods = re.findall(
        r'^\s+at ((?:PerfView(?:Extensibility)?|Microsoft\.Diagnostics|System|Commands)\.[\w.`+<>]+)\(',
        text, re.M)
    return {'exception_types': [kind for kind in kinds if re.search(r'\b' + kind + r'\b', text)],
            'compiler_codes': sorted(set(re.findall(r'\berror (CS[0-9]{4})\b', text))),
            'methods': sorted(set(methods))[:20]}


class CpuProfile:
    def __init__(self, root, name, pid, seconds=90):
        self.root, self.name, self.pid = Path(root), name, pid
        self.output = self.root / 'raw' / (name + '-cpu')
        self.output.mkdir(parents=True, exist_ok=True)
        self.log = (self.output / 'driver.log').open('w')
        script = Path(__file__).resolve().parent.parent / 'network-diagnostics' / 'Measure-MoshCpu.ps1'
        self.child = subprocess.Popen([
            'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', str(script), '-TargetProcessId', str(pid),
            '-DurationSeconds', str(seconds), '-OutputDirectory', str(self.output)],
            stdout=self.log, stderr=subprocess.STDOUT)

    def finish(self):
        try:
            if self.child.wait(timeout=420):
                raise RuntimeError('Exact-PID CPU/network capture failed: ' + self.name)
            for source in self.output.glob('*.json'):
                shutil.copyfile(source, self.root / (self.name + '-' + source.name))
            self.export_callers()
        finally:
            self.log.close()

    def export_callers(self):
        raw = self.output / 'raw'
        tool = raw / 'tools' / 'PerfView.exe'
        trace = raw / 'cpu.etl'
        prepare = Path(__file__).resolve().parent / 'Prepare-StackExporter.ps1'
        try:
            with (raw / 'stack-export.log').open('w') as log:
                subprocess.run([
                    'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', str(prepare), '-Tool', str(tool)],
                    stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
                subprocess.run([
                    str(tool), '/AcceptEula', '/NoGui',
                    '/LogFile:' + str(raw / 'stack-symbols.log'),
                    'userCommand', 'ProbeStacks.SaveExactCpuStacks', str(trace), str(self.pid),
                    str(raw / 'cpu.perfView.xml.zip')],
                    stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            self.record_export_error(raw)
            raise
        export_stacks(raw / 'cpu.perfView.xml.zip', self.pid,
                      self.root / (self.name + '-callers.json'))

    def record_export_error(self, raw):
        texts = []
        for name in ['stack-export.log', 'stack-symbols.log']:
            path = raw / name
            if path.exists():
                texts.append(path.read_text(errors='replace'))
        (self.root / (self.name + '-export-error.json')).write_text(
            json.dumps(error_summary('\n'.join(texts)), indent=2), encoding='utf-8')
