// Derives the persistence-status warning from `nativeRuntimeStatusProvider`
// (1-в-1 with React `useRuntimePersistenceStatus` in
// src/features/private-dm/use-runtime-persistence-status.ts). Pure/testable:
// returns a structured `PersistenceWarning` (kind + raw reason) and never
// touches BuildContext/AppLocalizations, so i18n stays in the widget layer.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Discriminator mirroring the two branches of React's `useRuntimePersistenceStatus`:
/// the persistence-not-encrypted branch (`unavailable`) and the gateway-threw
/// branch (`error`).
enum PersistenceWarningKind { unavailable, error }

/// Structured warning carried to the widget, which formats the localized
/// title/body. `reason` is the raw string (persistence error for `unavailable`,
/// thrown error message for `error`); the widget applies the leading-space
/// " Reason: " / "Reason: " prefix per React.
class PersistenceWarning {
  const PersistenceWarning({required this.kind, this.reason});
  final PersistenceWarningKind kind;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceWarning &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          reason == other.reason;

  @override
  int get hashCode => kind.hashCode ^ reason.hashCode;
}

/// `FutureProvider<PersistenceWarning?>` deriving from
/// `nativeRuntimeStatusProvider` (the gateway seam, ADR 0013). Mirrors React's
/// `useRuntimePersistenceStatus` try/catch: browser-demo link-mode -> null;
/// persistence available && encryptedAtRest -> null; otherwise `unavailable`
/// with the persistence error; on gateway throw -> `error` with the message.
/// Awaiting the upstream `.future` inside try/catch maps the gateway error to
/// the `error` warning without rethrowing, matching React's `catch`.
final persistenceWarningProvider =
    FutureProvider<PersistenceWarning?>((ref) async {
  final NativeRuntimeStatus status;
  try {
    status = await ref.watch(nativeRuntimeStatusProvider.future);
  } catch (error) {
    // React: `catch (error): reason = error instanceof Error ? error.message : String(error)`.
    return PersistenceWarning(
      kind: PersistenceWarningKind.error,
      reason: error.toString(),
    );
  }
  // React: `if (!status || status.moss.link_mode === "browser-demo") return null`.
  if (status.moss.linkMode == 'browser-demo') {
    return null;
  }
  // React: `if (status.persistence.available && status.persistence.encrypted_at_rest) return null`.
  if (status.persistence.available && status.persistence.encryptedAtRest) {
    return null;
  }
  // React: `reason = status.persistence.error ? ` Reason: ${error}` : ""`.
  return PersistenceWarning(
    kind: PersistenceWarningKind.unavailable,
    reason: status.persistence.error,
  );
});
