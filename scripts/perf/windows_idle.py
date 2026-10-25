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
import statistics
from cpu_profile import CpuProfile

APP = Path(sys.argv[1]).resolve()
ROOT = Path(sys.argv[2]).resolve()
SCRIPTS = Path(__file__).parent.resolve()
PROBE = SCRIPTS / 'idle-api.exe'
MESSAGES_PER_DM = int(sys.argv[3]) if len(sys.argv) > 3 else 1
REUSE_FIXTURE = sys.argv[4:] == ['--reuse-ci-fixture']
if len(sys.argv) > 4 and not REUSE_FIXTURE:
    raise ValueError('Unknown profiling option')
if not 1 <= MESSAGES_PER_DM <= 100:
    raise ValueError("The diagnostic history budget is one to 100 messages per DM")
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
    text = re.sub(r'([?&]token=)[^\s"<>]+', r'\1<redacted>', text)
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
        send_history(owner, other, sid, index)
        print('Established and delivered fixture DM', index, MESSAGES_PER_DM, flush=True)
        return sid
    finally:
        other.stop()


def fixture_bodies(index):
    return ['Idle profiling fixture ' + str(index)] + [
        f'Idle profiling fixture {index} message {number}'
        for number in range(1, MESSAGES_PER_DM)]


def send_history(owner, other, session, index):
    bodies = fixture_bodies(index)
    for body in bodies:
        owner.ask('send', session=session, body=body)

    def delivered():
        received = other.ask('poll', session=session)['messages']
        sent = owner.ask('poll', session=session)['messages']
        received_bodies = {m['body'] for m in received}
        acknowledged = {m['body'] for m in sent if m['status'] in ['delivered', 'read']}
        return set(bodies) <= received_bodies and set(bodies) <= acknowledged

    wait_until(delivered)


def powershell(script, *args):
    subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', str(SCRIPTS / script), *map(str, args)], check=True)


def check_window(pid, name, moment, minimized):
    path = ROOT / (name + '-window-' + moment + '.json')
    powershell('Open-ProfileChat.ps1', '-TargetProcessId', pid, '-Inspect', '-OutputFile', path)
    state = json.loads(path.read_text(encoding='utf-8-sig'))
    assert state['pid'] == pid and state['visible'], 'Expected the owned visible HWND'
    assert state['iconic'] == minimized, 'Unexpected minimized state'


def measure(pid, name, minimized, seconds=90):
    check_window(pid, name, 'before', minimized)
    CpuProfile(ROOT, name, pid, seconds).finish()
    check_window(pid, name, 'after', minimized)
    samples = json.loads((ROOT / (name + '-process-samples.json')).read_text(encoding='utf-8-sig'))
    network = json.loads((ROOT / (name + '-network-summary.json')).read_text(encoding='utf-8-sig'))
    assert network['complete'] and network['control_validated'], 'Incomplete network capture'
    assert len(samples) > 10, 'Missing process CPU samples'
    elapsed = samples[-1]['second'] - samples[0]['second']
    cpu_ms = samples[-1]['cpu_ms'] - samples[0]['cpu_ms']
    assert elapsed > 0 and cpu_ms >= 0, 'Invalid process counter interval'
    result = {'pid': pid, 'elapsed_seconds': elapsed, 'cpu_ms': cpu_ms,
              'cpu_one_core_percent': 100 * cpu_ms / (elapsed * 1000),
              'rss_median_bytes': statistics.median(s['working_set_bytes'] for s in samples)}
    (ROOT / (name + '.json')).write_text(json.dumps(result, indent=2))
    print(name, 'CPU', round(result['cpu_one_core_percent'], 3), flush=True)
    return result


def warm(name):
    started = time.monotonic()
    tick = 0
    while time.monotonic() - started < 480:
        if tick % 60 == 0:
            print(name, 'warmup', tick // 60, flush=True)
        time.sleep(1)
        tick += 1


def seed_fixture(data):
    owner = Peer(data)
    try:
        for index in range(8):
            pair(owner, index)
        owner.ask('seed', channel='idleprof-' + uuid.uuid4().hex[:16])
        assert owner.ask('read') == {'dm': 8, 'groups': 2, 'channels': 1}
        (ROOT / 'native-inventory.json').write_text(json.dumps(checked_inventory(owner)))
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
        visible = measure(app.pid, 'gui-visible', minimized=False)
        powershell('Open-ProfileChat.ps1', '-TargetProcessId', app.pid, '-Hide')
        time.sleep(5)
        hidden = measure(app.pid, 'gui-hidden', minimized=True)
        return {'visible': visible, 'hidden': hidden}
    finally:
        # This is our disposable fixture process on an ephemeral runner.
        subprocess.run(['taskkill', '/PID', str(app.pid), '/T', '/F'], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        app.wait(timeout=15)


def inventory(data, filename='gui-inventory.json'):
    owner = Peer(data)
    try:
        state = owner.ask('read')
        state.update(checked_inventory(owner))
        (ROOT / filename).write_text(json.dumps(state))
        assert {k: state[k] for k in ['dm', 'groups', 'channels']} == {'dm': 8, 'groups': 2, 'channels': 1}
    finally:
        owner.stop()


def checked_inventory(owner):
    value = owner.ask('inventory')
    assert value['pending_invitations'] == 0, 'Unexpected pending invitations'
    bodies = value.pop('bodies')
    expected = sorted(body for i in range(8) for body in fixture_bodies(i))
    assert bodies == expected, 'Changed fixture messages'
    value['message_bodies_sha256'] = hashlib.sha256(json.dumps(bodies).encode()).hexdigest()
    return value


def prepare_fixture(data):
    marker = data / '.idle-profiler-fixture'
    if REUSE_FIXTURE:
        if os.environ.get('GITHUB_ACTIONS') != 'true' or not marker.is_file():
            raise RuntimeError('Reuse requires an owned synthetic CI fixture')
        if marker.read_text() != 'synthetic-ci-fixture-v1':
            raise RuntimeError('Unknown synthetic fixture marker')
        inventory(data, 'native-inventory.json')
        return
    if data.exists():
        raise RuntimeError('Refusing an existing application data directory')
    seed_fixture(data)
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        marker.write_text('synthetic-ci-fixture-v1')


def main():
    # Match path_provider_windows' company/product convention for this EXE.
    data = Path(os.environ['APPDATA']) / 'app.mosh' / 'mosh'
    manifest = {'fixture': {'offline_dm': 8, 'groups': 2, 'channels': 1,
                             'messages_per_dm': MESSAGES_PER_DM},
                'fixture_reused': REUSE_FIXTURE,
                'runtime_source': os.environ['IDLE_RUNTIME_SOURCE'],
                'warmup_seconds': 480, 'window_seconds': 90,
                'hashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [APP / 'mosh.exe', APP / 'mosh_core.dll',
                                     APP / 'moss.dll', APP / 'flutter_windows.dll', APP / 'data/app.so']}}
    (ROOT / 'fingerprint.json').write_text(json.dumps(manifest, indent=2))
    prepare_fixture(data)
    gui = gui_profile(data)
    inventory(data)
    (ROOT / 'comparison.json').write_text(json.dumps({'gui': gui}, indent=2))
    print('COMPLETE: visible, minimized and restored inventory', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        (ROOT / 'failure.json').write_text(json.dumps({'type': type(error).__name__, 'message': redact(str(error))}))
        print('Profile failed: ' + type(error).__name__ + ': ' + redact(str(error)), file=sys.stderr)
        sys.exit(1)
