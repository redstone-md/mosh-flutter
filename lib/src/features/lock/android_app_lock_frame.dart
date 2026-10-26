import 'package:flutter/widgets.dart';
import 'android_app_access.dart';

/// Startup/setup also acknowledges a safe frame before any chat route is mounted.
class AndroidAppLockFrame extends StatefulWidget {
  const AndroidAppLockFrame(
      {super.key, required this.access, required this.child});
  final AndroidAppAccess access;
  final Widget child;
  @override
  State<AndroidAppLockFrame> createState() => _AndroidAppLockFrameState();
}

class _AndroidAppLockFrameState extends State<AndroidAppLockFrame> {
  @override
  void initState() {
    super.initState();
    widget.access.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.access.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.access.protectedFrameReady();
    });
    return widget.child;
  }
}
