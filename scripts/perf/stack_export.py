"""Export selected-process call paths, without PerfView command-line metadata."""
from collections import Counter
import json
from pathlib import PureWindowsPath
import re
import xml.etree.ElementTree as ET
import zipfile


PROCESS = re.compile(r'^Process(?:32|64)?\s+\S+\s+\((\d+)\)(?:\s|$)')


def frame_name(value):
    if PROCESS.match(value):
        return '[selected process]'
    thread = re.match(r'^Thread \((\d+)\)', value)
    if thread:
        return '[thread ' + thread[1] + ']'
    if '!' in value:
        module, symbol = value.split('!', 1)
        return PureWindowsPath(module).name + '!' + symbol
    return PureWindowsPath(value).name if '\\' in value else value


def read_paths(root, pid):
    frames = {int(e.attrib['ID']): e.text or '' for e in root.iter('Frame')}
    stacks = {int(e.attrib['ID']): (int(e.attrib['FrameID']), int(e.attrib['CallerID']))
              for e in root.iter('Stack')}
    paths = Counter()
    skipped = Counter()
    for sample in root.iter('Sample'):
        cursor = int(sample.attrib['StackID'])
        path, processes, seen = [], [], set()
        while cursor >= 0:
            if cursor in seen or len(seen) >= 512:
                raise ValueError('Cyclic or overlong caller stack')
            seen.add(cursor)
            frame, cursor = stacks[cursor]
            text = frames[frame]
            match = PROCESS.match(text)
            if match:
                processes.append(int(match[1]))
            path.append(frame_name(text))
        metric = float(sample.attrib.get('Metric', '1'))
        if processes != [pid]:
            skipped['foreign' if processes else 'without_process'] += metric
            continue
        paths[tuple(path)] += metric
    if not paths:
        raise ValueError('No exact-PID caller stacks')
    return paths, skipped


def export_stacks(source, pid, output):
    with zipfile.ZipFile(source) as archive:
        names = [n for n in archive.namelist() if n.endswith('.xml')]
        if len(names) != 1:
            raise ValueError('Expected one PerfView stack source')
        with archive.open(names[0]) as stream:
            paths, skipped = read_paths(ET.parse(stream).getroot(), pid)
    flat, inclusive = Counter(), Counter()
    for path, metric in paths.items():
        flat[path[0]] += metric
        for frame in set(path):
            inclusive[frame] += metric
    result = {'pid': pid, 'sampled_weight': sum(paths.values()),
              'skipped_weight': dict(skipped),
              'flat': flat.most_common(), 'inclusive': inclusive.most_common(),
              'paths': [{'weight': weight, 'frames': list(path)}
                        for path, weight in paths.most_common()],
              'note': 'Exact-PID exported call stacks; native/Go/AOT unwinds can be incomplete. Inclusive paths overlap. No raw trace or command-line metadata.'}
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result
