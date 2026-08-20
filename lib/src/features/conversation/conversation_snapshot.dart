/// One view over the three conversation snapshots.
///
/// A DM, a channel and a group poll back three different generated types.
/// The shared list, row, body and controller read this view instead, so
/// there is one message shape and one snapshot shape in the UI.
///
/// The view is sealed: the fields every kind has sit on the base, and each
/// kind keeps its own source snapshot. The header, the peer-status drawer
/// and the kind-only banners read that source, so nothing needs a cast.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelMessage, ChannelSnapshot;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        AttachmentDescriptor,
        AttachmentView,
        CallEvent,
        ChatMessage,
        SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupMessage, GroupSnapshot;

/// One message, whatever kind of conversation it came from.
///
/// [own] is worked out while mapping, because each kind decides it
/// differently: a DM compares device names, a channel and a group compare
/// fingerprints.
@immutable
class ConversationMessage {
  const ConversationMessage({
    required this.fromDevice,
    required this.body,
    required this.own,
    this.fromFingerprint,
    this.messageId,
    this.sentAtMs,
    this.attachment,
    this.callEvent,
    this.deliveryStatus,
    this.deliveryError,
    this.retryable,
  });

  final String fromDevice;
  final String body;

  /// Whether the local device sent this message.
  final bool own;

  /// The sender's device fingerprint. Null in a DM: there is only one peer,
  /// so the runtime does not send a fingerprint per message.
  final String? fromFingerprint;

  final String? messageId;
  final BigInt? sentAtMs;
  final AttachmentDescriptor? attachment;

  /// A call started, ended or was missed. DMs only.
  final CallEvent? callEvent;

  final MessageDeliveryStatus? deliveryStatus;
  final String? deliveryError;
  final bool? retryable;

  /// What consecutive rows are grouped by: the fingerprint where there is
  /// one, the device name in a DM.
  String get senderKey => fromFingerprint ?? fromDevice;

  /// Whether the row offers a Retry button: an own message that failed and
  /// the runtime says can be sent again.
  bool get canRetry =>
      own &&
      deliveryStatus == MessageDeliveryStatus.failed &&
      retryable == true &&
      messageId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationMessage &&
          runtimeType == other.runtimeType &&
          fromDevice == other.fromDevice &&
          body == other.body &&
          own == other.own &&
          fromFingerprint == other.fromFingerprint &&
          messageId == other.messageId &&
          sentAtMs == other.sentAtMs &&
          attachment == other.attachment &&
          callEvent == other.callEvent &&
          deliveryStatus == other.deliveryStatus &&
          deliveryError == other.deliveryError &&
          retryable == other.retryable;

  @override
  int get hashCode => Object.hash(
        fromDevice,
        body,
        own,
        fromFingerprint,
        messageId,
        sentAtMs,
        attachment,
        callEvent,
        deliveryStatus,
        deliveryError,
        retryable,
      );
}

/// One conversation, ready to render. Match on the subtype to reach the
/// source snapshot when a kind-only surface needs it.
@immutable
sealed class ConversationSnapshot {
  const ConversationSnapshot({
    required this.target,
    required this.ownDeviceName,
    required this.ownFingerprint,
    required this.messages,
    required this.attachments,
  });

  /// Which conversation this is. Also the key of the provider family.
  final AnyConversationTarget target;

  /// The local device's display name.
  final String ownDeviceName;

  /// The local device's fingerprint.
  final String ownFingerprint;

  final List<ConversationMessage> messages;
  final List<AttachmentView> attachments;

  /// The snapshot this view was built from. Two views are equal when their
  /// sources are, which keeps a poll that changed nothing from rebuilding
  /// the conversation.
  Object get source;

  /// The attachment transfer state for [attachmentId], or null when the
  /// snapshot carries none. Attachment lists are short, so a scan is enough.
  AttachmentView? attachmentView(String attachmentId) {
    for (final view in attachments) {
      if (view.attachmentId == attachmentId) return view;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSnapshot &&
          runtimeType == other.runtimeType &&
          target == other.target &&
          source == other.source;

  @override
  int get hashCode => Object.hash(runtimeType, target, source);
}

/// A private DM.
final class DmConversation extends ConversationSnapshot {
  DmConversation(DmTarget target, this.source)
      : super(
          target: target,
          ownDeviceName: source.displayName,
          ownFingerprint: source.fingerprint,
          messages: source.messages
              .map((m) => _fromDm(m, source.displayName))
              .toList(growable: false),
          attachments: source.attachments,
        );

  @override
  final SessionSnapshot source;
}

/// A public channel.
final class ChannelConversation extends ConversationSnapshot {
  ChannelConversation(ChannelTarget target, this.source)
      : super(
          target: target,
          ownDeviceName: source.displayName,
          ownFingerprint: source.deviceFingerprint,
          messages: source.messages
              .map((m) => _fromChannel(m, source.deviceFingerprint))
              .toList(growable: false),
          attachments: source.attachments,
        );

  @override
  final ChannelSnapshot source;
}

/// A private or org group.
final class GroupConversation extends ConversationSnapshot {
  GroupConversation(GroupTarget target, this.source)
      : super(
          target: target,
          ownDeviceName: source.displayName,
          ownFingerprint: source.deviceFingerprint,
          messages: source.messages
              .map((m) => _fromGroup(m, source.deviceFingerprint))
              .toList(growable: false),
          attachments: source.attachments,
        );

  @override
  final GroupSnapshot source;
}

/// A DM message. Own is the device name match the DM runtime uses, and a DM
/// carries no per-message fingerprint.
ConversationMessage _fromDm(ChatMessage m, String ownDeviceName) =>
    ConversationMessage(
      fromDevice: m.fromDevice,
      body: m.body,
      own: m.fromDevice == ownDeviceName,
      messageId: m.messageId,
      sentAtMs: m.sentAtMs,
      attachment: m.attachment,
      callEvent: m.callEvent,
      deliveryStatus: m.deliveryStatus,
      deliveryError: m.deliveryError,
      retryable: m.retryable,
    );

/// A channel or group message. Both are multi-party, so own is a fingerprint
/// match: two members can share a display name but never a fingerprint.
///
/// `ChannelMessage` and `GroupMessage` are field-identical but share no
/// generated base, so the caller reads the fields off its own type and this
/// builds the view.
ConversationMessage _fromMultiParty({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  required String ownFingerprint,
  String? messageId,
  BigInt? sentAtMs,
  AttachmentDescriptor? attachment,
  MessageDeliveryStatus? deliveryStatus,
  String? deliveryError,
  bool? retryable,
}) =>
    ConversationMessage(
      fromDevice: fromDevice,
      body: body,
      own: fromFingerprint == ownFingerprint,
      fromFingerprint: fromFingerprint,
      messageId: messageId,
      sentAtMs: sentAtMs,
      attachment: attachment,
      deliveryStatus: deliveryStatus,
      deliveryError: deliveryError,
      retryable: retryable,
    );

ConversationMessage _fromChannel(ChannelMessage m, String ownFingerprint) =>
    _fromMultiParty(
      fromDevice: m.fromDevice,
      fromFingerprint: m.fromFingerprint,
      body: m.body,
      ownFingerprint: ownFingerprint,
      messageId: m.messageId,
      sentAtMs: m.sentAtMs,
      attachment: m.attachment,
      deliveryStatus: m.deliveryStatus,
      deliveryError: m.deliveryError,
      retryable: m.retryable,
    );

ConversationMessage _fromGroup(GroupMessage m, String ownFingerprint) =>
    _fromMultiParty(
      fromDevice: m.fromDevice,
      fromFingerprint: m.fromFingerprint,
      body: m.body,
      ownFingerprint: ownFingerprint,
      messageId: m.messageId,
      sentAtMs: m.sentAtMs,
      attachment: m.attachment,
      deliveryStatus: m.deliveryStatus,
      deliveryError: m.deliveryError,
      retryable: m.retryable,
    );
