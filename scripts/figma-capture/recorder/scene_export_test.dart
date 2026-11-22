// Run: flutter test scripts/figma-capture/recorder/scene_export_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_select.dart';

import 'scene_export.dart';

/// Exports the current frame and returns every painted scope of scene.json.
Future<List<Map<String, Object?>>> exportScopes(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('scene_export_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  await exportScene(tester, 'test', 'Test', outDir: dir.path);
  final scene = jsonDecode(File('${dir.path}/scene.json').readAsStringSync())
      as Map<String, Object?>;
  final scopes = <Map<String, Object?>>[];
  void walk(Map<String, Object?> node) {
    if (node['t'] == 'g') scopes.add(node);
    for (final child in node['c'] as List? ?? const []) {
      if (child is Map<String, Object?>) walk(child);
    }
  }

  walk(scene['tree']! as Map<String, Object?>);
  return scopes;
}

void main() {
  testWidgets('a generic lib widget names its layers', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MoshSelect<int>(
          label: 'Size',
          value: 1,
          options: const [MoshSelectOption(1, 'One')],
          onChanged: (_) {},
        ),
      ),
    ));

    final scopes = await exportScopes(tester);

    expect(scopes.map((s) => s['lib']), contains('MoshSelect'));
  });

  testWidgets('layers carry their Material control and its state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          FilledButton(onPressed: () {}, child: const Text('Send')),
          const OutlinedButton(onPressed: null, child: Text('Retry')),
          const TextField(decoration: InputDecoration(errorText: 'Required')),
          Switch(value: true, onChanged: (_) {}),
        ]),
      ),
    ));

    final scopes = await exportScopes(tester);
    final controls = {
      for (final s in scopes)
        if (s['control'] != null) s['control']: s['controlState'],
    };

    expect(controls, {
      'FilledButton': null,
      'OutlinedButton': 'disabled',
      'TextField': 'error',
      'Switch': 'on',
    });
  });
}
