"""Executable examples of the CI guard's allowed and forbidden forms."""
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'test_policy', pathlib.Path(__file__).with_name('test-policy.py'))
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)
ISSUE = 'https://linear.app/ivoxygen/issue/IVO-123/example'


class TestPolicy(unittest.TestCase):
    def test_forbidden_forms(self):
        cases = {
            'focus': ["test.only('x', () => {})", "describe . only ('x', f)",
                      'test("x", {only: true}, f)', 'test("x", solo: true)',
                      'test("x", {"only": true}, f)'],
            'skip': ["test.skip('x', f)", "it.todo('x')", 'test("x", skip: gate)',
                     '@Skip("reason")', '#[ignore = "reason"]', '#[ignore]',
                     '@unittest.skipIf(gate, "reason")', 'self.skipTest("why")',
                     '@unittest.skip("broken")', '@pytest.mark.skip(reason="broken")',
                     'test("x", {"skip": true}, f)'],
            'timeout': ['test("x", timeout: Timeout(Duration(minutes: 4)))',
                        '@Timeout(Duration(minutes: 4))',
                        'test("x", { timeout: 9000 }, f)',
                        'test("x", {"timeout": 9000}, f)'],
            'retry': ['test("x", retry: 3)', 'test("x", { retries: 2 }, f)',
                      'test("x", {"retries": 2}, f)'],
            'wait': ['await Future<void>.delayed(Duration(seconds: 1))',
                     'thread::sleep(Duration::from_secs(1));',
                     'setTimeout(resolve, 500)', 'sleep(2)'],
        }
        for rule, sources in cases.items():
            for source in sources:
                with self.subTest(source=source):
                    self.assertEqual([r for _, r in policy.violations(source)], [rule])

    def test_allowed_forms_and_non_code(self):
        for source in [
            'TargetPlatformVariant.only(TargetPlatform.windows)',
            'items.skip(1)', 'EdgeInsets.only(bottom: 2)',
            'test("x", {only: false}, f)',
            'ProviderContainer(retry: (_, __) => null)',
            'LockScreen(retry: callback)',
            'test("x", () => { const config = {retry: 3, skip: true}; })',
            'testWidgets("x", (t) async { Widget(timeout: 3); })',
            'await operation.future', 'await tester.pump(Duration(seconds: 1))',
            '// test.only("x", f)\n/* skip: true */',
            '# test.only("x", f)',
            'final text = "test.only(skip: true)";',
            'final text = r"""test.only(skip: true)""";',
            'let text = r#"test.only(skip: true)"#;',
        ]:
            with self.subTest(source=source):
                self.assertEqual(policy.violations(source), [])

    def test_exceptions_require_local_reason_and_tracking_issue(self):
        source = 'await sleep(2);'
        valid = f'// test-policy: wait {ISSUE} -- real-process carrier deadline\n'
        self.assertEqual(policy.violations(valid + source), [])
        for comment in [
            '// test-policy: wait -- no issue\n',
            f'// test-policy: wait {ISSUE} -- short\n',
            valid + '\n', valid.replace('wait', 'skip'),
            valid.replace(ISSUE, 'https://linear.app/not-an-issue'),
        ]:
            self.assertTrue(policy.violations(comment + source))
        self.assertTrue(policy.violations(source + f' "{valid.strip()}"'))
        self.assertTrue(policy.violations(valid.replace('wait', 'focus') +
                                         'test.only("x", f)'))

    def test_baseline_freezes_expression_and_multiplicity_but_never_focus(self):
        original = 'await sleep(2);'
        self.assertEqual(policy.violations(original, original), [])
        self.assertTrue(policy.violations('await sleep(3);', original))
        self.assertTrue(policy.violations(original + '\n' + original, original))
        annotation = '#[ignore = "native worker"]\nfn native() {}\nfn fast() {}'
        self.assertEqual(policy.violations(annotation + '\nfn other() {}', annotation), [])
        source = 'test.only("x", f)'
        self.assertTrue(policy.violations(source, source))
        original = 'test("x",\n timeout: Timeout(Duration(seconds: 4)))'
        self.assertTrue(policy.violations(original.replace('4', '5'), original))

    def test_file_scope_and_git_baseline(self):
        self.assertTrue(policy.test_source('test/support/helper.dart'))
        self.assertTrue(policy.test_source('mosh-core/src/foo/tests.rs'))
        self.assertTrue(policy.test_source('mosh-media/engine/tests/flow.rs'))
        self.assertTrue(policy.test_source('scripts/foo.test.mjs'))
        self.assertFalse(policy.test_source('lib/src/foo.dart'))
        self.assertFalse(policy.test_source('moss/test/foo.rs'))
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            path = root / 'test' / 'example.dart'
            path.parent.mkdir()
            path.write_text('await sleep(2);')
            subprocess.run(['git', 'add', '.'], cwd=root, check=True)
            subprocess.run(['git', '-c', 'user.name=ForeverInLaw', '-c',
                            'user.email=test@example.com', 'commit', '-qm',
                            'test: baseline'], cwd=root, check=True)
            self.assertEqual(policy.check(root, 'HEAD'), [])
            (root / 'test' / 'new.dart').write_text('test.only("x", f)')
            self.assertEqual(len(policy.check(root, 'HEAD')), 1)
            (root / 'test' / 'new.dart').write_text('test("x", f)')
            path.write_text('await sleep(3);')
            self.assertEqual(len(policy.check(root, 'HEAD')), 1)
            with self.assertRaises(subprocess.CalledProcessError):
                policy.check(root, 'invalid-ref')


if __name__ == '__main__':
    unittest.main()
