import json
from pathlib import Path
import tempfile
import unittest

from compare_idle_profiles import compare


class IdleComparisonTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write(self.root, 'provenance.json', {
            'candidate_moss_sha256': 'candidate', 'order': 'before-after'})
        for name in ['before', 'after']:
            root = self.root / name
            root.mkdir()
            self.write(root, 'fingerprint.json', {
                'runtime_source': 'unchanged-app',
                'fixture_reused': name == 'after',
                'fixture': {'offline_dm': 8, 'groups': 2, 'channels': 1, 'messages_per_dm': 100},
                'warmup_seconds': 480, 'window_seconds': 90,
                'hashes': {key: ('candidate' if name == 'after' else 'baseline')
                          if key == 'moss.dll' else 'identical'
                          for key in ['mosh.exe', 'mosh_core.dll', 'moss.dll',
                                      'flutter_windows.dll', 'app.so']}})
            inventory = {'dm': 8, 'groups': 2, 'channels': 1,
                         'pending_invitations': 0, 'message_bodies_sha256': 'golden'}
            for filename in ['native-inventory.json', 'gui-inventory.json']:
                self.write(root, filename, inventory)
            for phase in ['gui-visible', 'gui-hidden']:
                self.write(root, phase + '.json', {'elapsed_seconds': 89, 'cpu_ms': 10})
                self.write(root, phase + '-network-summary.json',
                           {'complete': True, 'control_validated': True})

    @staticmethod
    def write(root, name, value):
        (root / name).write_text(json.dumps(value))

    def alter(self, name, change):
        path = self.root / 'after' / name
        value = json.loads(path.read_text())
        change(value)
        path.write_text(json.dumps(value))

    def test_accepts_only_the_moss_binary_change(self):
        self.assertEqual(compare(self.root)['after']['message_bodies_sha256'], 'golden')

    def test_rejects_an_application_binary_change(self):
        self.alter('fingerprint.json', lambda v: v['hashes'].update({'mosh_core.dll': 'different'}))
        with self.assertRaises(AssertionError):
            compare(self.root)

    def test_rejects_changed_history(self):
        self.alter('gui-inventory.json', lambda v: v.update({'message_bodies_sha256': 'changed'}))
        with self.assertRaises(AssertionError):
            compare(self.root)

    def test_rejects_incomplete_network_capture(self):
        self.alter('gui-visible-network-summary.json', lambda v: v.update({'complete': False}))
        with self.assertRaises(AssertionError):
            compare(self.root)
