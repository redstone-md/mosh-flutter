import 'package:flutter/material.dart';

void main() {
  runApp(const MoshApp());
}

class MoshApp extends StatelessWidget {
  const MoshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mosh',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const MoshHome(),
    );
  }
}

class MoshHome extends StatelessWidget {
  const MoshHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mosh')),
      body: const Center(child: Text('Mosh 0.8.0-dev')),
    );
  }
}
