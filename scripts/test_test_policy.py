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
    def check_rust(self, source, original='', name='mosh-core/src/audio_devices.rs'):
        """Exercise real file selection and immutable Git-baseline comparison."""
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            path = root / name
            path.parent.mkdir(parents=True)
            path.write_text(original)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            subprocess.run(['git', 'add', '.'], cwd=root, check=True)
            subprocess.run(['git', '-c', 'user.name=ForeverInLaw', '-c',
                            'user.email=test@example.com', 'commit', '-qm',
                            'test: baseline'], cwd=root, check=True)
            path.write_text(source)
            return [error.split(': ')[1] for error in policy.check(root, 'HEAD')]

    def test_inline_rust_ignore_requires_tracking_issue(self):
        for source in [
            '#[cfg(test)] mod tests { #[test]\n'
            '#[ignore = "untracked regression"] fn validation() {} }',
            '#[ignore = "untracked regression"]\n#[test] fn validation() {}',
            '#[test]\n#[ignore = "untracked regression"] fn validation() {}',
            '#[cfg(feature = "native")] mod native {\n'
            '#[cfg(all(test, target_os = "windows"))] mod checks {\n'
            '#[ignore = "untracked regression"]\n#[test] fn validation() {} }}',
            '#[cfg(test)] mod tests { #[test]\n'
            '#[cfg_attr(target_os = "windows", ignore = "untracked regression")]\n'
            'fn validation() {} }',
        ]:
            with self.subTest(source=source):
                self.assertEqual(self.check_rust(source), ['skip'])

    def test_inline_rust_wait_baseline_freezes_value_and_multiplicity(self):
        wait = 'std::thread::sleep(std::time::Duration::from_secs(2));'
        original = '#[cfg(all(feature = "native", test))] mod tests {\n' \
            'fn wait_for_peer() { ' + wait + ' }}'
        self.assertEqual(self.check_rust(original, original), [])
        for source in [original.replace('(2)', '(3)'),
                       original.replace(wait, wait + wait)]:
            with self.subTest(source=source):
                self.assertEqual(self.check_rust(source, original), ['wait'])
        self.assertEqual(self.check_rust(original), ['wait'])
        self.assertEqual(self.check_rust(original, name='mosh-media/engine/src/frames.rs'),
                         ['wait'])
        production = 'fn runtime() { ' + wait + ' }'
        self.assertEqual(self.check_rust(production + original, production), ['wait'])

    def test_inline_rust_local_exceptions_and_existing_gates(self):
        skip = f'// test-policy: skip {ISSUE} -- real native backend is required\n'
        wait = f'// test-policy: wait {ISSUE} -- bounded real carrier completion\n'
        source = skip + '#[ignore = "native backend"]\n#[test]\nfn peer() {\n' \
            + wait + 'std::thread::sleep(Duration::from_secs(2));\n}'
        self.assertEqual(self.check_rust(source), [])
        conditional = source.replace('#[ignore = "native backend"]',
                                     '#[cfg_attr(windows, ignore = "native backend")]')
        self.assertEqual(self.check_rust(conditional), [])
        self.assertEqual(self.check_rust(source.replace(ISSUE, 'no-issue')), ['skip', 'wait'])
        gate = '#[cfg(all(test, target_os = "windows"))] mod native {\n' \
            '#[test]\n#[ignore = "native backend"] fn peer() {} }'
        self.assertEqual(self.check_rust(gate, gate), [])
        self.assertEqual(self.check_rust(gate), ['skip'])

    def test_inline_rust_cfg_nesting_and_attribute_order(self):
        for attributes in [
            '#[cfg(test)]',
            '#[cfg(feature = "native")]\n#[cfg(test)]',
            '#[cfg(all(feature = "native", any(test, all(test, unix))))]',
            '#[cfg(not(not(test)))]',
            '#[cfg(any(test, any()))]',
        ]:
            source = 'mod outer { ' + attributes + '\n#[allow(dead_code)]\n' \
                'mod checks { fn helper() { thread::sleep(Duration::from_secs(2)); } }}'
            with self.subTest(attributes=attributes):
                self.assertEqual(self.check_rust(source), ['wait'])
        for attributes in ['#[test]\n#[ignore]', '#[ignore]\n#[test]']:
            self.assertEqual(self.check_rust(attributes + '\nfn peer() {}'), ['skip'])
        for source in [
            '#![cfg(test)]\nfn helper() { sleep(2); }',
            'mod checks { #![cfg(test)] fn helper() { sleep(2); } }\n'
            'fn production() { sleep(99); }',
            '#[tokio :: test(flavor = "multi_thread")]\nfn peer() { sleep(2); }',
        ]:
            with self.subTest(source=source):
                self.assertEqual(self.check_rust(source), ['wait'])

    def test_inline_rust_const_generics_do_not_end_the_function_signature(self):
        prelude = 'struct Value<const N: usize>;\n' \
            'struct Outer<T>(std::marker::PhantomData<T>);\n'
        wait = 'std::thread::sleep(std::time::Duration::from_secs(2));'
        for signature in [
            'fn helper() -> Value<{ 1 + 2 }>',
            'fn helper() -> Outer<Outer<Value<{ 1 + 2 }>>>',
            "fn helper<'a>() -> Outer<fn(&'a str) -> "
            'Value<{ if 3 > 2 { 1 << 1 } else { 0 } }>>',
            'fn helper<F: Fn() -> Value<{ 1 + 2 }>>() -> Value<{ 1 + 2 }>',
        ]:
            source = prelude + '#[cfg(test)]\n' + signature + ' {\n' \
                + wait + '\npanic!("type fixture");\n}'
            with self.subTest(signature=signature):
                self.assertEqual(self.check_rust(source), ['wait'])
                self.assertEqual(self.check_rust(source, source), [])
                self.assertEqual(self.check_rust(source.replace('(2)', '(3)'), source),
                                 ['wait'])

    def test_rust_production_regions_and_lexical_lookalikes_are_excluded(self):
        source = '''
fn production() { thread::sleep(Duration::from_secs(42)); }
#[cfg(not(test))]
fn runtime_only() { thread::sleep(Duration::from_secs(23)); }
#[cfg(any(test, feature = "background"))]
fn shared_runtime() { thread::sleep(Duration::from_secs(17)); }
#[cfg(any())]
fn dead_runtime() { thread::sleep(Duration::from_secs(12)); }
#[cfg(all(test, any()))]
fn dead_test_helper() { thread::sleep(Duration::from_secs(11)); }
const RAW: &str = r##"#[cfg(test)] mod fake { #[ignore] fn f() { sleep(9); } }"##;
/* #[cfg(test)] mod fake { /* nested comment */ #[ignore] fn f() { sleep(9); } } */
#[cfg(test)]
mod checks {
    fn borrow<'a, 'b>(one: &'a str, two: &'b str) -> &'a str { one }
    #[test]
    fn syntax() {
        let brace = '}';
        let escaped = '\\u{7d}';
        let bytes = br###" /* #[ignore] sleep(8); } "###;
        let text = "#[ignore] sleep(7); }";
        /* outer /* inner } */ sleep(6); */
    }
}
'''
        continuation = 'continued \\' + '\nthread::sleep(Duration::from_secs(9));'
        for prefix in ['', 'b', 'c']:
            source = source.replace('let text =',
                                    f'let continued = {prefix}"{continuation}";\nlet text =')
        self.assertEqual(self.check_rust(source), [])
        source = source.replace('let text =', 'thread::sleep(Duration::from_secs(2)); let text =')
        self.assertEqual(self.check_rust(source), ['wait'])
        line = source[:source.index('thread::sleep(Duration::from_secs(2)); let text =')].count('\n') + 1
        self.assertEqual(policy.violations(
            policy.scoped_source('mosh-core/src/audio_devices.rs', source), is_rust=True),
            [(line, 'wait')])
        forged = f'const NOTE: &str = r"// test-policy: skip {ISSUE} -- native backend absent";\n'
        self.assertEqual(self.check_rust(forged + '#[test]\n#[ignore] fn f() {}'), ['skip'])

    def test_rust_integration_file_keeps_whole_file_policy(self):
        source = 'fn helper() { thread::sleep(Duration::from_secs(2)); }\n' \
            '#[ignore = "untracked"]\n#[test] fn peer() {}'
        self.assertCountEqual(self.check_rust(source, name='mosh-core/tests/peer.rs'),
                              ['wait', 'skip'])
        self.assertEqual(self.check_rust(source, source, name='mosh-core/tests/peer.rs'), [])

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
                        'test("x", {"timeout": 9000}, f)',
                        'await operation.timeout(Duration(seconds: 2))',
                        'await operation . timeout (Duration(seconds: 2))',
                        'await socket.timeout(Duration(seconds: 2), onTimeout: stop)'],
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
            'operation.timeoutLabel()', 'operation.timeout',
            'final text = "operation.timeout(Duration(seconds: 2))";',
            '// operation.timeout(Duration(seconds: 2))',
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

    def test_an_itsaplan_key_tracks_an_exception(self):
        source = 'await sleep(2);'
        valid = '// test-policy: wait MOSH-19 -- real-process carrier deadline\n'
        self.assertEqual(policy.violations(valid + source), [])
        for key in ['MOSH-', 'MOSH-19x', 'IVO-19', 'mosh-19']:
            self.assertTrue(policy.violations(valid.replace('MOSH-19', key) + source))

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

    def test_future_timeout_requires_local_exception_and_freezes_old_budget(self):
        source = 'await result.timeout(const Duration(seconds: 2));'
        valid = f'// test-policy: timeout {ISSUE} -- retain the existing callback deadline\n'
        self.assertEqual(policy.violations(valid + source), [])
        self.assertEqual(policy.violations(source, source), [])
        for changed in [source.replace('2', '3'), source + '\n' + source]:
            self.assertTrue(policy.violations(changed, source))
        for comment in [valid + '\n', valid.replace('timeout', 'wait'),
                        valid.replace(ISSUE, 'https://example.com/issue')]:
            self.assertTrue(policy.violations(comment + source))

    def test_case_libraries_require_one_real_group_scoped_owner(self):
        case = 'void main() { test("contract", () {}); }'
        runner = ("import 'contract_cases.dart' as cases;\n"
                  "group('contract', cases.main);")
        sources = {'test/unit/contract_cases.dart': case}
        self.assertTrue(policy.case_registrations(sources))
        sources['test/unit/unit_test.dart'] = runner
        self.assertEqual(policy.case_registrations(sources), [])
        sources['test/unit/another_test.dart'] = runner
        self.assertTrue(policy.case_registrations(sources))
        del sources['test/unit/another_test.dart']
        for invalid in [runner.replace("group('contract', cases.main)", 'cases.main()'),
                        '// ' + runner.replace('\n', '\n// '),
                        runner.replace("group('contract', cases.main)",
                                       '\"group(contract, cases.main)\"')]:
            sources['test/unit/unit_test.dart'] = invalid
            self.assertTrue(policy.case_registrations(sources))
        # Existing case-builder helpers declare no main and need no runner.
        self.assertEqual(policy.case_registrations(
            {'test/support/conversation_cases.dart': 'List cases() => [];'}), [])

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
