import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:mosh/src/features/crash_reporting/crash_report_scrubber.dart';

void main() {
  final scrubber = CrashReportScrubber(salt: 'salt-a');
  const peer = 'a3f9c2e81b7d4f60a3f9c2e81b7d4f60';

  test('invites and addresses leave nothing behind', () {
    final out = scrubber.scrub(
      'join mosh://invite?mesh=m&session=s#fp=abc failed '
      'via /ip4/203.0.113.7/tcp/4001 and 198.51.100.2:9000 '
      'and [2001:db8::1] at 12:34:56',
    );
    expect(out, isNot(contains('mosh://')));
    expect(out, isNot(contains('203.0.113.7')));
    expect(out, isNot(contains('198.51.100.2')));
    expect(out, isNot(contains('2001:db8::1')));
    expect(out, contains('12:34:56'), reason: 'a clock is not an address');
  });

  test('OS user names are cut out of paths', () {
    final out = scrubber.scrub(
      r'open C:\Users\ivan\AppData\mosh.log and /home/olga/.mosh',
    );
    expect(out, isNot(contains('ivan')));
    expect(out, isNot(contains('olga')));
    expect(out, contains('AppData'));
  });

  test('ids hash stably per install and differ across installs', () {
    final first = scrubber.scrub('send to $peer failed');
    expect(first, isNot(contains(peer)));
    expect(scrubber.scrub('retry $peer'), contains(_token(first)));
    final other = CrashReportScrubber(salt: 'salt-b').scrub('send to $peer');
    expect(_token(other), isNot(_token(first)));
  });

  test('event text, messages and native paths are scrubbed in place', () {
    final event = SentryEvent(
      message: SentryMessage('dial 203.0.113.7'),
      exceptions: [
        SentryException(
          type: 'FrbException',
          value: 'no session for $peer',
          stackTrace: SentryStackTrace(frames: [
            SentryStackFrame(absPath: '/home/olga/mosh/libmosh_core.so'),
          ]),
        ),
      ],
      serverName: 'olga-laptop',
      user: SentryUser(id: 'x'),
    );
    final out = scrubber.scrubEvent(event);
    expect(out.message!.formatted, isNot(contains('203.0.113.7')));
    expect(out.exceptions!.single.value, isNot(contains(peer)));
    expect(out.exceptions!.single.stackTrace!.frames.single.absPath,
        isNot(contains('olga')));
    expect(out.serverName, isNull);
    expect(out.user, isNull);
  });
}

String _token(String scrubbed) =>
    RegExp(r'<id:[0-9a-f]+>').firstMatch(scrubbed)!.group(0)!;
