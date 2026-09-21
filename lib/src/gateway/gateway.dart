// Sealed seam between the flutter_rust_bridge surface and the Flutter UI.
//
// The app runs on `RealBridgeGateway`; tests run on the scriptable gateway in
// test/support/. Widgets depend on `Gateway`, never on a concrete impl, so
// swapping the wired runtime is one provider change (ADR 0013).
//
// This interface is deliberately narrow: it is the conversation seam, and it
// is the test surface (ADR 0025). Eight methods -- the typed poll plus the
// seven shared actions -- each take a [ConversationTarget] instead of coming
// in a DM, a channel and a group flavour, so callers stop dispatching on the
// kind (ADR 0017). For the six shared actions the adapter converts the target
// to one typed ref and calls one shared bridge function; the dispatch lives
// in the bridge (ADR 0024).
//
// Everything that only mirrors one generated bridge call 1:1 -- org, VPN,
// call, diagnostics, session setup, the channel/group joins and lists -- is
// NOT part of this interface. Those callers reach `BridgeFacade`
// (bridge_facade.dart) directly, because faking a pass-through wholesale is
// what once made the test double mirror 42 methods.
//
// The voice-call audio adapters (capture, playback, ringtone) also stay
// outside this seam on purpose: they wrap OS audio (record/cpal) through
// their own factory providers and hold no Rust domain state, so there is
// nothing here to fake or swap (ADR 0025).

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;

/// Abstraction over the conversation seam.
///
/// Implementations: `RealBridgeGateway` (delegates to the generated frb
/// functions) in the app, and `ScriptableGateway` (test/support/) in tests.
/// Widgets consume this interface, never a concrete class, so the wired
/// backend is a single Riverpod provider swap.
abstract interface class Gateway {
  /// Reads [target]'s current state. The snapshot type follows the kind:
  /// a DM polls back a [SessionSnapshot], a channel a [ChannelSnapshot],
  /// a group a [GroupSnapshot].
  ///
  /// An implementation also implements [ConversationSnapshotReader] and hands
  /// itself to the target, which is what keeps the return type honest without
  /// a cast. The reader is not part of this interface: callers never see it.
  Future<S> poll<S>(ConversationTarget<S> target);

  /// Sends a text message to [target].
  ///
  /// The message's delivery status arrives with the next [poll], so the
  /// caller invalidates its snapshot after this returns instead of reading
  /// a result here.
  Future<void> send(AnyConversationTarget target, {required String body});

  /// Re-sends a failed outbound message of [target] by its id. Same
  /// delivery-status rule as [send]: read it from the next [poll].
  Future<void> retry(AnyConversationTarget target, {required String messageId});

  /// Sends a file to [target]. The caller reads the picked file into base64
  /// and adds a thumbnail or voice metadata when it has them. There is no
  /// result: the new attachment's id and hash arrive with the next [poll]
  /// (ADR 0024 drops the success payload).
  Future<void> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  });

  /// Starts the inbound transfer of one of [target]'s attachments. Progress
  /// surfaces in the next [poll] snapshot. Opening a finished file is
  /// client-side and has no Rust function.
  Future<void> downloadAttachment(AnyConversationTarget target,
      {required String attachmentId});

  /// Stops an in-flight transfer of one of [target]'s attachments.
  Future<void> cancelAttachment(AnyConversationTarget target,
      {required String attachmentId});

  /// Clears a DM offer from [target]'s offer list. The accept path dismisses
  /// the offer itself after acceptInvite; this is the decline path. A DM
  /// holds no offers, which is why the parameter is a [DmOfferHost].
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
      {required String offerId});

  /// Leaves [target]: closes the DM session, leaves the channel, or closes
  /// the group. The caller invalidates its snapshot and navigates away.
  Future<void> leave(AnyConversationTarget target);

  /// Tells the counterpart the local user is typing (DMs and groups; a
  /// channel has no counterpart to tell and this is a no-op for it).
  /// Fire-and-forget: the runtime throttles repeats to its own cadence, so
  /// the composer may call this on every keystroke.
  Future<void> typingSignal(AnyConversationTarget target);

  /// Reports the conversation is on screen, auto-triggering the DM read
  /// receipts for every not-yet-read counterpart message when the toggle
  /// is on. Groups and channels have no receipts in this slice, so this
  /// is a no-op for them.
  Future<void> markViewed(AnyConversationTarget target);
}
