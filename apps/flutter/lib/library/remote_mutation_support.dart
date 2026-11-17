import 'package:flutterustmusic/authentication/credential_vault.dart';

typedef CredentialRejectionContinuation = Future<void> Function();

/// Preserves an operation-specific typed result while handing explicit
/// credential rejection to the owning session continuation or vault.
Future<T> finishRemoteMutationCredentialRejection<T>({
  required T result,
  required bool credentialRejected,
  required CredentialVault credentialVault,
  required T cleanupFailureResult,
  CredentialRejectionContinuation? continueSession,
}) async {
  if (!credentialRejected) {
    return result;
  }
  if (continueSession != null) {
    try {
      // The write itself is never replayed: continuation only repairs the
      // shared session for later reads and mutations. Its owner performs any
      // definitive vault cleanup when reauthentication is actually required.
      await continueSession();
    } on Object {
      // A transient continuation failure must retain the last durable
      // credential. The original mutation remains rejected/unknown.
    }
    return result;
  }
  try {
    await credentialVault.delete();
    return result;
  } on Object {
    return cleanupFailureResult;
  }
}
