#!/usr/bin/env python3
"""Guard new test hazards without rewriting historical native/timing suites."""
import collections
import pathlib
import re
import subprocess
import sys

BASELINE = '3b2b88eb9fc49081be28b98c375c52fd7948adae'
# Mask comments and literals before looking for executable syntax. This is a
# lexical guard, not a replacement for the Dart/Rust parsers or code review.
LEXEMES = re.compile(
    r'/\*[\s\S]*?\*/|//[^\n]*|#(?!\s*\[)[^\n]*|'
    r'r(#+)?"[\s\S]*?"\1|'
    r"(?:r)?'''[\s\S]*?'''|(?:r)?\"\"\"[\s\S]*?\"\"\"|"
    r"'(?:\\.|[^'\\\n])*'|\"(?:\\.|[^\"\\])*\"|`(?:\\.|[^`\\])*`"
)
TEST_CALL = r'\b(?:test|testWidgets|it|describe|group)(?:\s*\.\s*\w+)*'
RULES = {
    'focus': re.compile(TEST_CALL + r'\s*\.\s*only\s*\(|\b(?:solo|only)\s*:\s*true\b'),
    'skip': re.compile(TEST_CALL + r'\s*\.\s*(?:skip|todo)\s*\(|'
                       r'\b(?:skip|todo)\s*:|@Skip\s*\(|#\s*\[\s*ignore\b|'
                       r'\b(?:skipTest|skipIf|skipUnless|skipif|xfail)\s*\(|'
                       r'\b(?:unittest|pytest\s*\.\s*mark)\s*\.\s*skip\s*\('),
    'timeout': re.compile(r'\b(?:timeout|testTimeout)\s*:|@Timeout\s*\('),
    'retry': re.compile(r'\b(?:retry|retries)\s*:'),
    'wait': re.compile(r'\bFuture\s*(?:<[^>]*>)?\s*\.\s*delayed\s*\(|'
                       r'\b(?:sleep|setTimeout|setInterval)\s*\('),
}
APPROVAL = re.compile(
    r'test-policy: (skip|timeout|retry|wait) '
    r'(https://(?:linear\.app/[\w-]+/issue/[A-Z][A-Z0-9]*-\d+(?:/[^\s]*)?|'
    r'github\.com/[^/\s]+/[^/\s]+/issues/\d+))'
    r' -- (\S[^\n]{9,})'
)


def mask(source):
    def replacement(match):
        text = match[0]
        # Quoted JS option keys are syntax, not test-name/fixture strings.
        key = text[1:-1]
        if (text[0] in ("'", '"') and key in (
                'only', 'solo', 'skip', 'todo', 'timeout', 'retry', 'retries')
                and re.match(r'\s*:', source[match.end():])):
            return ' ' + key + ' '
        return re.sub(r'[^\n]', ' ', text)
    return LEXEMES.sub(replacement, source)


def expression_end(code, start):
    """Include argument values, so changing an existing budget is a new risk."""
    depth = 0
    for i in range(start, len(code)):
        char = code[i]
        if char in '([{':
            depth += 1
        elif char in ')]}':
            if depth == 0:
                return i
            depth -= 1
            if depth == 0:
                return i + 1
        elif char in ',;' and depth == 0:
            return i
    return len(code)


def enclosing_call(code, position):
    stack = []
    for i, char in enumerate(code[:position]):
        if char in '([{':
            stack.append((char, i))
        elif char in ')]}' and stack:
            stack.pop()
    for char, i in reversed(stack):
        if char == '{' and re.search(r'(?:=>|\)\s*(?:async)?)\s*$', code[:i]):
            return ''
        if char == '(':
            name = re.search(r'([\w.]+)\s*$', code[:i])
            return name[1].split('.')[-1] if name else ''
    return ''


def hazards(source):
    code = mask(source)
    found = []
    for rule, pattern in RULES.items():
        for match in pattern.finditer(code):
            if (rule in ('skip', 'retry', 'timeout') and ':' in match[0]
                    and enclosing_call(code, match.start()) not in (
                        'test', 'testWidgets', 'it', 'describe', 'group')):
                continue
            end = expression_end(code, match.start())
            signature = re.sub(r'\s+', '', source[match.start():end])
            line = source.count('\n', 0, match.start()) + 1
            found.append((rule, signature, line))
    return found


def violations(source, original=''):
    remaining = collections.Counter((r, s) for r, s, _ in hazards(original))
    comments = [(source.count('\n', 0, m.start()) + 1, m[0])
                for m in LEXEMES.finditer(source)
                if m[0].startswith(('//', '/*', '#'))]
    errors = []
    for rule, signature, line in hazards(source):
        if rule != 'focus' and remaining[rule, signature]:
            remaining[rule, signature] -= 1
            continue
        # An exception is local to the hazardous line (or the line before).
        comment = '\n'.join(text for at, text in comments if line - 1 <= at <= line)
        approved = any(m[1] == rule for m in APPROVAL.finditer(comment))
        if rule == 'focus' or not approved:
            errors.append((line, rule))
    return errors


def test_source(name):
    path = pathlib.PurePosixPath(name)
    if path.suffix == '.dart':
        return name.startswith(('test/', 'native_test/', 'integration_test/'))
    if path.suffix in ('.mjs', '.js', '.py'):
        return name.startswith('scripts/') and (
            '.test.' in name or path.name.startswith('test_'))
    if path.suffix == '.rs':
        return name.startswith(('mosh-core/', 'mosh-media/')) and (
            '/tests/' in name or 'test' in path.stem)
    return False


def case_registrations(sources):
    """Each case library has one group-scoped owner in its feature directory."""
    owners = collections.defaultdict(list)
    imports = re.compile(
        r"\bimport\s+['\"]([\w]+_cases\.dart)['\"]\s+as\s+(\w+)\s*;"
    )
    for name, source in sources.items():
        if not name.endswith('_test.dart'):
            continue
        code = mask(source)
        for match in imports.finditer(source):
            if code[match.start():match.start() + 6] != 'import':
                continue
            alias = re.escape(match[2])
            groups = re.findall(r'\bgroup\s*\([^,]*,\s*' + alias +
                                r'\.main\s*\)', code)
            target = str(pathlib.PurePosixPath(name).parent / match[1])
            owners[target].extend([name] * len(groups))
    errors = []
    for name, source in sources.items():
        if name.endswith('_cases.dart') and re.search(r'\bvoid\s+main\s*\(', mask(source)):
            if len(owners[name]) != 1:
                errors.append(f'{name}: expected one group-scoped runner, found '
                              f'{len(owners[name])}')
    return errors


def check(root, baseline):
    # Fail closed on shallow/missing history; do not quietly accept all tests.
    subprocess.run(['git', 'cat-file', '-e', baseline + '^{commit}'],
                   cwd=root, check=True)
    names = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        cwd=root).decode().split('\0')
    sources = {name: (root / name).read_text()
               for name in sorted(set(filter(test_source, names)))
               if (root / name).is_file()}
    errors = case_registrations(sources)
    for name, source in sources.items():
        if not hazards(source):
            continue
        old = subprocess.run(['git', 'show', baseline + ':' + name], cwd=root,
                             capture_output=True, text=True)
        for line, rule in violations(source, old.stdout if old.returncode == 0 else ''):
            errors.append(f'{name}:{line}: {rule}: use event/clock waits or add '
                          'a local test-policy exception with issue URL and reason')
    return errors


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    errors = check(root, BASELINE)
    print('\n'.join(errors) if errors else 'Test policy passed.')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
