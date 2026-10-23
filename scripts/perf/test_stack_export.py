import unittest
import xml.etree.ElementTree as ET

from stack_export import read_paths


FIXTURE = r'''<StackSource><Frames>
<Frame ID="0">Process64 mosh (17) Args: sensitive-fixture-argument</Frame>
<Frame ID="1">C:\fixture\mosh_core.dll!hot_function</Frame>
<Frame ID="2">Process64 mosh (42) Args: foreign-private-argument</Frame>
</Frames><Stacks>
<Stack ID="0" FrameID="0" CallerID="-1"/>
<Stack ID="1" FrameID="1" CallerID="0"/>
<Stack ID="2" FrameID="2" CallerID="-1"/>
<Stack ID="3" FrameID="1" CallerID="2"/>
<Stack ID="4" FrameID="1" CallerID="-1"/>
</Stacks><Samples>
<Sample StackID="1" Metric="2"/><Sample StackID="1"/>
<Sample StackID="3" Metric="8"/><Sample StackID="4" Metric="4"/>
</Samples></StackSource>'''


class StackExportTest(unittest.TestCase):
    def test_exact_pid_excludes_foreign_and_removes_metadata(self):
        paths, skipped = read_paths(ET.fromstring(FIXTURE), 17)
        self.assertEqual(dict(paths), {('mosh_core.dll!hot_function', '[selected process]'): 3})
        self.assertEqual(dict(skipped), {'foreign': 8, 'without_process': 4})

    def test_empty_or_foreign_only_fails(self):
        with self.assertRaisesRegex(ValueError, 'No exact-PID'):
            read_paths(ET.fromstring(FIXTURE), 99)

    def test_bad_cycle_fails(self):
        root = ET.fromstring(FIXTURE)
        root.find('./Stacks/Stack').set('CallerID', '1')
        with self.assertRaisesRegex(ValueError, 'Cyclic'):
            read_paths(root, 17)


if __name__ == '__main__':
    unittest.main()
