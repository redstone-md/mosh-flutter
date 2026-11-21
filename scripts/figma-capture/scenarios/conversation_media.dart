// Seeded attachments, voice notes and call-log entries.
part of 'conversation_fixtures.dart';

/// A landscape photo on disk, for attachments that finished downloading.
/// Call it inside a test: the file is deleted when the test ends.
String landscapeFile(String name, {int seed = 0}) {
  final path = '${Directory.systemTemp.path}/mosh-figma-$name';
  final file = File(path)
    ..writeAsBytesSync(base64Decode(landscapePng(w: 1200, h: 800, seed: seed)));
  addTearDown(() => file.existsSync() ? file.deleteSync() : null);
  return path;
}

/// Photos, a clip and documents in every transfer state.
({List<ChatMessage> messages, List<AttachmentView> transfers}) dmAttachments(
    {bool onDisk = false}) {
  final harbour = file('a1', 'harbour.jpg', 'image/jpeg', 2840000,
      thumb: landscapePng(seed: 0));
  final ridge = file('a2', 'ridge-trail.jpg', 'image/jpeg', 3120000,
      thumb: landscapePng(seed: 1));
  final clip = file('a3', 'waves.mp4', 'video/mp4', 18400000,
      thumb: landscapePng(seed: 1));
  final route = file('a4', 'coast-route.pdf', 'application/pdf', 1260000);
  final list = file(
      'a5',
      'packing-list.docx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      48200);
  final tides = file(
      'a6',
      'tide-tables.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      96400);
  final map = file('a7', 'trail-map.zip', 'application/zip', 24800000);
  return (
    messages: [
      dmMsg(
          'm4', false, 'The route with all the stops', at(hour: 8, minute: 15),
          attachment: route),
      dmMsg('m5', false, '', at(hour: 8, minute: 16), attachment: map),
      dmMsg('m6', true, '', at(hour: 8, minute: 20),
          attachment: list, read: true),
      dmMsg('m7', true, '', at(hour: 8, minute: 21),
          attachment: tides,
          status: MessageDeliveryStatus.failed,
          error: 'transfer interrupted',
          retryable: true),
      dmMsg('m3', false, '', at(hour: 9, minute: 0), attachment: clip),
      dmMsg('m1', false, 'Look what I found from last summer',
          at(hour: 9, minute: 2),
          attachment: harbour),
      dmMsg('m2', true, '', at(hour: 9, minute: 6),
          attachment: ridge, read: true),
    ],
    transfers: [
      transfer('a1', AttachmentState.available,
          localPath: onDisk ? landscapeFile('harbour.jpg') : null),
      transfer('a2', AttachmentState.available,
          direction: 'outgoing',
          localPath: landscapeFile('ridge.jpg', seed: 1)),
      transfer('a3', AttachmentState.offered),
      transfer('a4', AttachmentState.downloading, done: 7, chunks: 12),
      transfer('a5', AttachmentState.failed),
      transfer('a6', AttachmentState.available, direction: 'outgoing'),
    ],
  );
}

/// Voice notes both ways, one still downloading.
({List<ChatMessage> messages, List<AttachmentView> transfers}) dmVoice() {
  AttachmentDescriptor voice(String id, int ms, int seed) =>
      file(id, 'voice-$id.m4a', 'audio/mp4', ms * 4,
          voice: VoiceMeta(durationMs: ms, peaksB64: voicePeaks(seed)));
  return (
    messages: [
      dmMsg('v0', false, 'Quick update from the trailhead',
          at(hour: 10, minute: 1)),
      dmMsg('v1', false, '', at(hour: 10, minute: 2),
          attachment: voice('v1', 14000, 1)),
      dmMsg('v2', true, '', at(hour: 10, minute: 4),
          attachment: voice('v2', 38000, 3), read: true),
      dmMsg('v3', false, '', at(hour: 10, minute: 9),
          attachment: voice('v3', 72000, 5)),
      dmMsg('v4', true, 'Sounds windy up there!', at(hour: 10, minute: 11)),
    ],
    transfers: [
      transfer('v1', AttachmentState.available),
      transfer('v2', AttachmentState.available, direction: 'outgoing'),
      transfer('v3', AttachmentState.downloading, done: 2, chunks: 5),
    ],
  );
}

/// Every call-log entry kind.
List<ChatMessage> dmCalls() {
  CallEvent call(String kind, int seconds, String id) => CallEvent(
      kind: kind, durationMs: BigInt.from(seconds * 1000), callId: id);
  return [
    dmMsg('c1', false, '', at(daysAgo: 1, hour: 19, minute: 2),
        call: call('missed', 0, 'c1')),
    dmMsg('c2', true, '', at(daysAgo: 1, hour: 19, minute: 10),
        call: call('completed', 1394, 'c2')),
    dmMsg('c3', false, 'Sorry, missed you earlier! Call later?',
        at(daysAgo: 1, hour: 19, minute: 40)),
    dmMsg('c4', false, '', at(hour: 7, minute: 45),
        call: call('completed', 312, 'c4')),
    dmMsg('c5', true, '', at(hour: 8, minute: 3),
        call: call('missed', 0, 'c5')),
    dmMsg('c6', false, '', at(hour: 8, minute: 20),
        call: call('update_required', 0, 'c6')),
  ];
}
