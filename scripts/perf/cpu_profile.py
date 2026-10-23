"""Exact-PID collector and sanitized caller stacks for a disposable CI fixture."""
import json
from pathlib import Path
import shutil
import subprocess

from stack_export import export_stacks


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
        # SaveCPUStacks selects by name. Validate the one disposable GUI, then
        # independently retain only exported stacks carrying its exact PID.
        ids = subprocess.check_output([
            'powershell.exe', '-NoProfile', '-Command',
            '@(Get-Process -Name mosh).Id | ConvertTo-Json -Compress'], text=True)
        value = json.loads(ids)
        if (value if isinstance(value, list) else [value]) != [self.pid]:
            raise RuntimeError('Expected exactly the owned Mosh GUI before stack export')
        with (raw / 'stack-export.log').open('w') as log:
            subprocess.run([
                str(tool), '/AcceptEula', '/NoGui',
                '/LogFile:' + str(raw / 'stack-symbols.log'),
                'userCommand', 'SaveCPUStacks', str(trace), 'mosh'],
                stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
        export_stacks(raw / 'cpu.perfView.xml.zip', self.pid,
                      self.root / (self.name + '-callers.json'))
