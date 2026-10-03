#!/usr/bin/env python3
"""Compare tracked source lines, including local dependency patches, at two refs."""
import argparse
import collections
import json
import pathlib
import subprocess

EXTENSIONS = {'.dart', '.rs', '.mjs', '.js', '.ts', '.py', '.sh', '.c', '.cpp',
              '.h', '.kt', '.swift', '.patch', '.ps1', '.cmd', '.cc', '.kts',
              '.gradle', '.cmake', '.podspec', '.iss', '.rc', '.html', '.svg'}


def git(*args):
    return subprocess.check_output(['git', *args])


def bucket(name):
    if name.startswith(('third_party/', 'rust_builder/cargokit/')):
        return 'dependency source and patches'
    if ('frb_generated' in name or name.startswith('lib/src/rust/')
            or name.startswith('lib/l10n/app_localizations')):
        return 'generated bridge'
    location = pathlib.PurePosixPath(name)
    if (name.startswith(('test/', 'integration_test/', 'native_test/'))
            or 'test' in location.stem or '/tests/' in name
            or '/history_tests/' in name or '/state_tests/' in name
            or '/runtime_tests/' in name):
        return 'tests'
    return 'application and tooling'


def measure(ref):
    totals = collections.Counter()
    # One batch avoids spawning a process for every source file.
    entries = git('ls-tree', '-r', '--full-tree', ref).decode().splitlines()
    sources = [(line.split()[2], line.split('\t', 1)[1]) for line in entries
               if line.split()[1] == 'blob']
    text_lines = 0
    process = subprocess.Popen(['git', 'cat-file', '--batch'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE)
    for oid, name in sources:
        process.stdin.write(f'{oid}\n'.encode())
        process.stdin.flush()
        header = process.stdout.readline().split()
        content = process.stdout.read(int(header[2]))
        process.stdout.read(1)
        location = pathlib.PurePosixPath(name)
        if location.suffix in EXTENSIONS or location.name == 'CMakeLists.txt':
            totals[bucket(name)] += len(content.splitlines())
        try:
            if b'\0' not in content:
                text_lines += len(content.decode('utf8').splitlines())
        except UnicodeDecodeError:
            pass
    process.stdin.close()
    if process.wait() != 0:
        raise RuntimeError('git cat-file failed')
    return totals, text_lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline')
    parser.add_argument('final', nargs='?', default='HEAD')
    args = parser.parse_args()
    (before, before_text), (after, after_text) = measure(args.baseline), measure(args.final)
    rows = []
    for name in sorted(before.keys() | after.keys()) + ['first-party source and tests', 'total source', 'all tracked text']:
        if name == 'all tracked text':
            first, last = before_text, after_text
        elif name == 'total source':
            first, last = sum(before.values()), sum(after.values())
        elif name == 'first-party source and tests':
            first = before['application and tooling'] + before['tests']
            last = after['application and tooling'] + after['tests']
        else:
            first, last = before[name], after[name]
        rows.append({'scope': name, 'before': first, 'after': last,
                     'removed': first - last,
                     'reduction_percent': round(100 * (first - last) / first, 2) if first else None})
    print(json.dumps({'baseline': args.baseline, 'final': args.final,
                      'extensions': sorted(EXTENSIONS), 'lines': rows}, indent=2))


if __name__ == '__main__':
    main()
