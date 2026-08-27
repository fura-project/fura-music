import 'package:flutterustmusic/authentication/credential_vault.dart';

/// Preserves an operation-specific typed result while applying the one shared
/// platform rule: only explicit credential rejection deletes persisted state.
Future<T> finishRemoteMutationCredentialRejection<T>({
  required T result,
  required bool credentialRejected,
  required CredentialVault credentialVault,
  required T cleanupFailureResult,
}) async {
  if (!credentialRejected) {
    return result;
  }
  try {
    await credentialVault.delete();
    return result;
  } on Object {
    return cleanupFailureResult;
  }
}
