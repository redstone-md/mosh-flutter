"""Measure the existing release DLL and EXE using a disposable real fixture."""
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import uuid

APP = Path(sys.argv[1]).resolve()
ROOT = Path(sys.argv[2]).resolve()
SCRIPTS = Path(__file__).parent.resolve()
PROBE = SCRIPTS / 'idle-api.exe'
ROOT.mkdir(parents=True, exist_ok=True)


class Peer:
    def __init__(self, directory, counterpart=False):
        directory.mkdir(parents=True, exist_ok=True)
        self.replies = queue.Queue()
        self.errors = (directory / 'probe-stderr.log').open('w')
        self.child = subprocess.Popen(
            [str(PROBE), str(APP / 'mosh_core.dll'), str(directory),
             'counterpart' if counterpart else 'owner'], cwd=APP,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors,
            text=True, encoding='utf-8')
        threading.Thread(target=self.read, daemon=True).start()
        try:
            assert self.replies.get(timeout=90) == {'ready': True}
        except queue.Empty:
            self.errors.flush()
            raise RuntimeError('API startup failed: ' + redact(
                (directory / 'probe-stderr.log').read_text(errors='replace')[-3000:]))

    def read(self):
        for line in self.child.stdout:
            if line.startswith('IDLE_REPLY '):
                self.replies.put(json.loads(line[len('IDLE_REPLY '):]))

    def ask(self, op, **values):
        self.child.stdin.write(json.dumps({'op': op, **values}) + '\n')
        self.child.stdin.flush()
        result = self.replies.get(timeout=90)
        if 'error' in result:
            raise RuntimeError('Fixture API operation failed: ' + op + ': ' + result['error'])
        return result

    def stop(self):
        if self.child.poll() is None:
            self.child.stdin.write('{"op":"exit"}\n')
            self.child.stdin.flush()
            self.child.wait(timeout=15)
        self.errors.close()


def wait_until(check):
    deadline = time.monotonic() + 90
    while not check():
        if time.monotonic() > deadline:
            raise RuntimeError('Real fixture connection/delivery did not finish')
        time.sleep(.1)


def redact(text):
    text = re.sub(r'mosh://\S+|\b[a-fA-F0-9]{32,}\b|\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?', '<redacted>', text)
    return text


def pair(owner, index):
    other = Peer(ROOT / ('counterpart-' + str(index)), counterpart=True)
    try:
        invite = owner.ask('invite')
        sid = invite['session']
        assert 0 < invite['port'] < 65536
        other.ask('accept', uri=invite['uri'], name=f'Offline {index}', port=55006 + index,
                  peer='127.0.0.1:' + str(invite['port']))

        def connected():
            states = [p.ask('poll', session=sid) for p in [owner, other]]
            progress = [{k: v for k, v in state.items() if k != 'messages'} for state in states]
            (ROOT / 'fixture-progress.json').write_text(json.dumps({'index': index, 'states': progress}))
            return all(state['state'] == 'connected' for state in states)

        wait_until(connected)
        body = 'Idle profiling fixture ' + str(index)
        owner.ask('send', session=sid, body=body)

        def delivered():
            received = other.ask('poll', session=sid)['messages']
            sent = owner.ask('poll', session=sid)['messages']
            return (any(m['body'] == body for m in received) and
                    any(m['body'] == body and m['status'] in ['delivered', 'read'] for m in sent))

        wait_until(delivered)
        print('Established and delivered fixture DM', index, flush=True)
        return sid
    finally:
        other.stop()


def powershell(script, *args):
    subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', str(SCRIPTS / script), *map(str, args)], check=True)


def measure(pid, name, poll=None, seconds=120):
    output = ROOT / (name + '.json')
    child = subprocess.Popen(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                              '-File', str(SCRIPTS / 'Measure-IdleProcess.ps1'),
                              '-TargetProcessId', str(pid), '-Seconds', str(seconds),
                              '-OutputFile', str(output)])
    tick = 0
    while child.poll() is None:
        if poll:
            poll(tick)
        tick += 1
        time.sleep(1)
    if child.returncode:
        raise RuntimeError('Measurement failed: ' + name)
    result = json.loads(output.read_text(encoding='utf-8-sig'))
    print(name, 'CPU', round(result['cpu_one_core_percent'], 3), flush=True)
    return result


def warm(name, poll=None):
    started = time.monotonic()
    tick = 0
    while time.monotonic() - started < 480:
        if poll:
            poll(tick)
        if tick % 60 == 0:
            print(name, 'warmup', tick // 60, flush=True)
        time.sleep(1)
        tick += 1


def native_profile(data, record=True):
    owner = Peer(data)
    try:
        sessions = [pair(owner, i) for i in range(8)]
        owner.ask('seed', channel='idleprof-' + uuid.uuid4().hex[:16])
        assert owner.ask('read') == {'dm': 8, 'groups': 2, 'channels': 1}
        (ROOT / 'native-inventory.json').write_text(json.dumps(owner.ask('inventory')))
        if not record:
            return None

        def poll(tick):
            owner.ask('read', session=sessions[-1])
            if tick % 5 == 0:
                owner.ask('plus')

        warm('native', poll)
        return measure(owner.child.pid, 'native-foreground', poll)
    finally:
        owner.stop()


def gui_profile(data):
    (data / 'first-run.json').write_text(json.dumps({
        'version': 1, 'displayName': 'Profile owner', 'step': 'name', 'completed': True}))
    app = subprocess.Popen([str(APP / 'mosh.exe')], cwd=APP,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        powershell('Open-ProfileChat.ps1', '-TargetProcessId', app.pid,
                   '-OutputFile', ROOT / 'app-ui.json')
        warm('GUI')
        foreground = measure(app.pid, 'gui-foreground')
        powershell('Open-ProfileChat.ps1', '-TargetProcessId', app.pid, '-Hide')
        time.sleep(5)
        hidden = measure(app.pid, 'gui-hidden')
        return {'foreground': foreground, 'hidden': hidden}
    finally:
        # This is our disposable fixture process on an ephemeral runner.
        subprocess.run(['taskkill', '/PID', str(app.pid), '/T', '/F'], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        app.wait(timeout=15)


def inventory(data):
    owner = Peer(data)
    try:
        state = owner.ask('read')
        state.update(owner.ask('inventory'))
        (ROOT / 'gui-inventory.json').write_text(json.dumps(state))
        assert {k: state[k] for k in ['dm', 'groups', 'channels']} == {'dm': 8, 'groups': 2, 'channels': 1}
    finally:
        owner.stop()


def main():
    # Match path_provider_windows' company/product convention for this EXE.
    data = Path(os.environ['APPDATA']) / 'app.mosh' / 'mosh'
    stage = sys.argv[3] if len(sys.argv) > 3 else 'all'
    manifest = {'fixture': {'offline_dm': 8, 'groups': 2, 'channels': 1},
                'warmup_seconds': 480, 'window_seconds': 120,
                'hashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [APP / 'mosh.exe', APP / 'mosh_core.dll',
                                     APP / 'moss.dll', APP / 'flutter_windows.dll', APP / 'data/app.so']}}
    if stage != 'gui':
        if data.exists():
            raise RuntimeError('Refusing an existing application data directory')
        (ROOT / 'fingerprint.json').write_text(json.dumps(manifest, indent=2))
        native = native_profile(data, os.environ.get('IDLE_MEASURE_NATIVE', 'true') == 'true')
        (ROOT / 'native-summary.json').write_text(json.dumps(native, indent=2))
    if stage != 'native':
        saved = json.loads((ROOT / 'fingerprint.json').read_text())
        assert saved == manifest and data.exists()
        native = json.loads((ROOT / 'native-summary.json').read_text())
        gui = gui_profile(data)
        inventory(data)
        (ROOT / 'comparison.json').write_text(json.dumps({'native': native, 'gui': gui}, indent=2))
    print('COMPLETE profiling stage:', stage, flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        (ROOT / 'failure.json').write_text(json.dumps({'type': type(error).__name__, 'message': redact(str(error))}))
        print('Profile failed: ' + type(error).__name__ + ': ' + redact(str(error)), file=sys.stderr)
        sys.exit(1)
