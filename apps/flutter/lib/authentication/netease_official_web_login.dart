import 'dart:typed_data';

enum OfficialWebLoginFailure { unavailable, alreadyRunning, failed }

class OfficialWebLoginException implements Exception {
  const OfficialWebLoginException(this.failure);

  final OfficialWebLoginFailure failure;

  @override
  String toString() => 'OfficialWebLoginException(${failure.name})';
}

/// Legacy boundary retained so authentication gateways and stored-session
/// verification do not have to change shape.
///
/// A generic external browser cannot return NetEase cookies to Fura without a
/// provider-owned OAuth redirect, while embedded WebKit proved unstable on
/// Linux. Active QR challenges use the separate external-confirmation handoff.
abstract interface class OfficialWebLoginBroker {
  bool get isSupported;
  Future<Uint8List?> authenticate();
  bool cancel();
}

class PlatformNeteaseOfficialWebLoginBroker implements OfficialWebLoginBroker {
  @override
  bool get isSupported => false;

  @override
  Future<Uint8List?> authenticate() => Future<Uint8List?>.error(
    const OfficialWebLoginException(OfficialWebLoginFailure.unavailable),
  );

  @override
  bool cancel() => false;
}
