"""Validate a same-host DLL comparison without claiming statistical CPU gains."""
import json
from pathlib import Path
import sys


def read(root, name):
    return json.loads((root / name).read_text(encoding='utf-8-sig'))


def fixture(root):
    fingerprint = read(root, 'fingerprint.json')
    assert fingerprint['fixture'] == {
        'offline_dm': 8, 'groups': 2, 'channels': 1, 'messages_per_dm': 100}
    before = read(root, 'native-inventory.json')
    after = read(root, 'gui-inventory.json')
    assert before['message_bodies_sha256'] == after['message_bodies_sha256']
    assert before['pending_invitations'] == after['pending_invitations'] == 0
    assert {k: after[k] for k in ['dm', 'groups', 'channels']} == {
        'dm': 8, 'groups': 2, 'channels': 1}
    return fingerprint, after['message_bodies_sha256']


def summarize(root):
    fingerprint, golden = fixture(root)
    assert fingerprint['warmup_seconds'] == 480 and fingerprint['window_seconds'] == 90
    phases = {}
    for phase in ['gui-visible', 'gui-hidden']:
        counters = read(root, phase + '.json')
        network = read(root, phase + '-network-summary.json')
        assert counters['elapsed_seconds'] >= 85 and counters['cpu_ms'] >= 0
        assert network['complete'] and network['control_validated']
        phases[phase] = {'process': counters, 'network': network}
    return {'fingerprint': fingerprint,
            'message_bodies_sha256': golden, 'phases': phases}


def compare(root):
    provenance = read(root, 'provenance.json')
    smoke, golden = fixture(root / 'candidate-smoke')
    assert read(root / 'candidate-smoke', 'comparison.json') == {'gui': {'package_smoke': True}}
    assert smoke['runtime_source'] == provenance['candidate_source']
    assert smoke['hashes']['moss.dll'] == provenance['candidate_moss_sha256']
    assert smoke['fixture_reused'] is False
    assert smoke['warmup_seconds'] == smoke['window_seconds'] == 0
    before, after = [summarize(root / name) for name in ['before', 'after']]
    assert before['message_bodies_sha256'] == after['message_bodies_sha256'] == golden
    assert before['fingerprint']['runtime_source'] == after['fingerprint']['runtime_source']
    before_hashes, after_hashes = [v['fingerprint']['hashes'] for v in [before, after]]
    assert set(before_hashes) == set(after_hashes) == {
        'mosh.exe', 'mosh_core.dll', 'moss.dll', 'flutter_windows.dll', 'app.so'}
    assert all(before_hashes[k] == after_hashes[k] for k in before_hashes if k != 'moss.dll')
    assert before_hashes['moss.dll'] != after_hashes['moss.dll']
    assert after_hashes['moss.dll'] == provenance['candidate_moss_sha256']
    order = provenance['order'].split('-')
    assert order in [['before', 'after'], ['after', 'before']]
    variants = {'before': before, 'after': after}
    assert all(variants[name]['fingerprint']['fixture_reused'] is True for name in order)
    return {'provenance': provenance, 'before': before, 'after': after,
            'limits': 'Two ordered public-network observations per host; '
                      'not a deterministic traffic replay or a statistically established patch gain.'}


if __name__ == '__main__':
    root = Path(sys.argv[1])
    (root / 'comparison.json').write_text(json.dumps(compare(root), indent=2))
    print('PASS: only Moss differs; full fixture inventory and both capture windows are valid.')
