import 'package:flutter/material.dart';
import 'package:mosh/src/features/crash_reporting/crash_reporting_toggle.dart';
import 'package:mosh/src/features/shared/read_receipts_toggle.dart';

class PrivacySettingsSection extends StatelessWidget {
  const PrivacySettingsSection({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrashReportingToggle(),
          SizedBox(height: 16),
          ReadReceiptsToggle(),
        ],
      );
}
