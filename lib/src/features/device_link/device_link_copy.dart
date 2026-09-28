import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/device_link/types.dart';

String deviceLinkError(AppLocalizations l, Object error) => deviceLinkErrorKind(
    l, error is DeviceLinkError ? error.kind : DeviceLinkErrorKind.unavailable);

String deviceLinkErrorKind(AppLocalizations l, DeviceLinkErrorKind kind) =>
    switch (kind) {
      DeviceLinkErrorKind.invalidQr => l.deviceLinkInvalidQr,
      DeviceLinkErrorKind.expired => l.deviceLinkExpired,
      DeviceLinkErrorKind.busy => l.deviceLinkBusy,
      DeviceLinkErrorKind.ineligible => l.deviceLinkIneligible,
      DeviceLinkErrorKind.codeMismatch => l.deviceLinkCodeMismatch,
      DeviceLinkErrorKind.rejected => l.deviceLinkRejected,
      DeviceLinkErrorKind.connectionLost => l.deviceLinkConnectionLost,
      DeviceLinkErrorKind.invalidRoster => l.deviceLinkInvalidRoster,
      DeviceLinkErrorKind.storage => l.deviceLinkStorageError,
      DeviceLinkErrorKind.unavailable => l.deviceLinkUnavailable,
    };

String deviceLinkPhase(AppLocalizations l, DeviceLinkPhase phase) =>
    switch (phase) {
      DeviceLinkPhase.idle => l.deviceLinkHelp,
      DeviceLinkPhase.showingQr => l.deviceLinkQrHelp,
      DeviceLinkPhase.connecting => l.deviceLinkConnecting,
      DeviceLinkPhase.awaitingApproval => l.deviceLinkApprovalHelp,
      DeviceLinkPhase.awaitingConfirmation => l.deviceLinkConfirmationHelp,
      DeviceLinkPhase.delivering => l.deviceLinkDelivering,
      DeviceLinkPhase.linked => l.deviceLinkSuccess,
      DeviceLinkPhase.failed => l.deviceLinkTryAgain,
    };
