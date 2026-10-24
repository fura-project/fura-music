import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/login_controller.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:flutterustmusic/authentication/netease_web_refresh_diagnostics.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

void main() {
  test('rejecting an unpersisted web candidate does not delete the previous saved session', () async {
    final previous = _document(1);
    final vault = _Vault(previous);
    final verification = _Verification()
      ..result.complete(CredentialVerificationResult.rejected);
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: _Broker(
        candidate: Uint8List.fromList(
          ascii.encode('MUSIC_U=rejected-candidate'),
        ),
      ),
      officialWebCredentialStager: (_) =>
          CredentialRestoreResult.verificationRequired,
      verificationOperationFactory: () => verification,
    );
    final outcome = await gateway.beginOfficialWebLogin().run();
    expect(outcome.authenticated, isFalse);
    expect(outcome.failure, OfficialWebAuthenticationFailure.rejected);
    expect(vault.deletes, 0);
    expect(vault.value, previous);
  });
  test('restart restores opaque V1/V2 through Pending and one account verification without a browser', () async {
    for (final version in [1, 2]) {
      final vault = _Vault(_document(version));
      final broker = _Broker();
      var authenticated = false;
      final verification = _Verification(
        onAuthenticated: () => authenticated = true,
      );
      final imported = <String>[];
      final gateway = RustNeteaseAuthenticationGateway(
        credentialVault: vault,
        officialWebLoginBroker: broker,
        authenticatedCredentialReader: () => authenticated,
        credentialImporter: (bytes) {
          expect(authenticated, isFalse);
          imported.add(utf8.decode(bytes!));
          return CredentialRestoreResult.verificationRequired;
        },
        verificationOperationFactory: () => verification,
      );
      final controller = LoginController(gateway);
      final restore = controller.restoreCredential();
      await pumpEventQueue();
      expect(controller.stage, LoginStage.verifyingStoredCredential);
      expect(authenticated, isFalse);
      expect(vault.lastRead, everyElement(0));
      verification.result.complete(CredentialVerificationResult.authenticated);
      await restore;
      expect(controller.stage, LoginStage.authenticated);
      expect(imported, [utf8.decode(_document(version))]);
      expect(verification.runs, 1);
      expect(broker.starts, 0);
      expect(vault.deletes, 0);
      controller.dispose();
    }
  });

  test('network failure retains V2 bytes and explicit retry verifies the same candidate', () async {
    final original = _document(2);
    final vault = _Vault(original);
    final first = _Verification();
    final retry = _Verification();
    var reservations = 0;
    var imports = 0;
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: _Broker(),
      authenticatedCredentialReader: () => false,
      credentialImporter: (_) {
        imports++;
        return CredentialRestoreResult.verificationRequired;
      },
      verificationOperationFactory: () => reservations++ == 0 ? first : retry,
    );
    final controller = LoginController(gateway);
    final restore = controller.restoreCredential();
    await pumpEventQueue();
    first.result.complete(CredentialVerificationResult.network);
    await restore;
    expect(controller.stage, LoginStage.verificationError);
    expect(controller.canRetryCredentialVerification, isTrue);
    expect(vault.value, original);
    expect(vault.deletes, 0);
    final verification = controller.verifyRestoredCredential();
    retry.result.complete(CredentialVerificationResult.authenticated);
    await verification;
    expect(controller.stage, LoginStage.authenticated);
    expect(imports, 1);
    expect(vault.value, original);
    controller.dispose();
  });

  test('explicit rejection deletes only the owning NetEase vault', () async {
    final vault = _Vault(_document(2));
    final operation = _Verification()
      ..result.complete(CredentialVerificationResult.rejected);
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: _Broker(),
      verificationOperationFactory: () => operation,
    );
    expect(
      await gateway.beginCredentialVerification().run(),
      CredentialVerificationResult.rejected,
    );
    expect(vault.value, isNull);
    expect(vault.deletes, 1);
  });

  test('late vault read cannot stage after logout even while browser cleanup is pending', () async {
    final vault = _Vault(_document(2))..readGate = Completer<Uint8List?>();
    final broker = _Broker()..cleanupGate = Completer<bool>();
    var imports = 0;
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: broker,
      credentialImporter: (_) {
        imports++;
        return CredentialRestoreResult.verificationRequired;
      },
      credentialSignOutCore: () => true,
    );
    final restore = gateway.restoreCredential();
    await pumpEventQueue();
    final logout = gateway.signOut();
    final stale = _document(2);
    vault.readGate!.complete(stale);
    expect(await restore, CredentialRestoreResult.coreUnavailable);
    expect(imports, 0);
    expect(stale, everyElement(0));
    broker.cleanupGate!.complete(true);
    expect(await logout, CredentialSignOutResult.signedOut);
    expect(vault.value, isNull);
  });

  test('provider retirement cancels a pending read before import and does not read another vault', () async {
    final retiredVault = _Vault(_document(2))
      ..readGate = Completer<Uint8List?>();
    var imports = 0;
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: retiredVault,
      officialWebLoginBroker: _Broker(),
      authenticatedCredentialReader: () => false,
      credentialImporter: (_) {
        imports++;
        return CredentialRestoreResult.verificationRequired;
      },
    );
    final controller = LoginController(gateway);
    final restoring = controller.restoreCredential();
    await pumpEventQueue();
    controller.dispose();
    final stale = _document(2);
    retiredVault.readGate!.complete(stale);
    await restoring;
    expect(imports, 0);
    expect(retiredVault.reads, 1);
    expect(retiredVault.deletes, 0);
    expect(stale, everyElement(0));
  });

  test('concurrent restores coalesce and the controller starts only one verification', () async {
    final vault = _Vault(_document(2))..readGate = Completer<Uint8List?>();
    var imports = 0;
    final verification = _Verification();
    final gateway = RustNeteaseAuthenticationGateway(
      credentialVault: vault,
      officialWebLoginBroker: _Broker(),
      authenticatedCredentialReader: () => false,
      credentialImporter: (_) {
        imports++;
        return CredentialRestoreResult.verificationRequired;
      },
      verificationOperationFactory: () => verification,
    );
    final controller = LoginController(gateway);
    final first = controller.restoreCredential();
    final second = controller.restoreCredential();
    await pumpEventQueue();
    expect(vault.reads, 1);
    vault.readGate!.complete(_document(2));
    await pumpEventQueue();
    expect(imports, 1);
    expect(verification.runs, 1);
    verification.result.complete(CredentialVerificationResult.authenticated);
    await Future.wait([first, second]);
    expect(controller.stage, LoginStage.authenticated);
    controller.dispose();
  });

  test(
    'new web login and persistence dominate old rejection and restore results',
    () async {
      final vault = _Vault(_document(1))..readGate = Completer<Uint8List?>();
      final oldVerification = _Verification();
      final exported = _document(2);
      var imports = 0;
      final gateway = RustNeteaseAuthenticationGateway(
        credentialVault: vault,
        officialWebLoginBroker: _Broker(),
        credentialImporter: (_) {
          imports++;
          return CredentialRestoreResult.verificationRequired;
        },
        credentialExporter: () =>
            bridge.QqMusicCredentialExport(secretBytes: exported),
        verificationOperationFactory: () => oldVerification,
      );
      final restore = gateway.restoreCredential();
      await pumpEventQueue();
      final rejected = gateway.beginCredentialVerification().run();
      gateway.beginOfficialWebLogin();
      final publication = gateway.persistAuthenticatedCredential();
      vault.readGate!.complete(_document(1));
      oldVerification.result.complete(CredentialVerificationResult.rejected);
      expect(await restore, CredentialRestoreResult.coreUnavailable);
      expect(await rejected, CredentialVerificationResult.replaced);
      expect(await publication, CredentialPersistenceResult.stored);
      expect(imports, 0);
      expect(vault.deletes, 0);
      expect(vault.value, _document(2));
      expect(exported, everyElement(0));
    },
  );

  test('browser candidate is staged, verified, then persists V2; failures keep previous vault', () async {
    for (final saveFails in [false, true]) {
      final previous = _document(1);
      final vault = _Vault(previous)..failWrites = saveFails;
      final broker = _Broker(
        candidate: Uint8List.fromList(
          ascii.encode(
            'MUSIC_U=synthetic-u; MUSIC_R_U=independent-r; __csrf=synthetic-c',
          ),
        ),
      );
      final verification = _Verification();
      final diagnostics = <String>[];
      var authenticated = false;
      final gateway = RustNeteaseAuthenticationGateway(
        credentialVault: vault,
        officialWebLoginBroker: broker,
        authenticatedCredentialReader: () => authenticated,
        officialWebCredentialStager: (bytes) {
          expect(authenticated, isFalse);
          expect(ascii.decode(bytes), contains('MUSIC_R_U=independent-r'));
          return CredentialRestoreResult.verificationRequired;
        },
        verificationOperationFactory: () => verification,
        credentialExporter: () {
          expect(authenticated, isTrue);
          return bridge.QqMusicCredentialExport(secretBytes: _document(2));
        },
        diagnostics: NeteaseWebRefreshDiagnostics(
          enabledOverride: true,
          sink: diagnostics.add,
        ),
      );
      final login = gateway.beginOfficialWebLogin().run();
      await pumpEventQueue();
      expect(broker.candidate, everyElement(0));
      expect(vault.writes, 0);
      authenticated = true;
      verification.result.complete(CredentialVerificationResult.authenticated);
      expect((await login).authenticated, isTrue);
      expect(
        await gateway.persistAuthenticatedCredential(),
        saveFails
            ? CredentialPersistenceResult.storageUnavailable
            : CredentialPersistenceResult.stored,
      );
      expect(vault.value, saveFails ? previous : _document(2));
      expect(diagnostics, [
        'FURA_NETEASE_WEB_REFRESH_DEBUG path=web_view phase=account_verification_entered success=true',
        'FURA_NETEASE_WEB_REFRESH_DEBUG path=web_view phase=secure_persistence success=${!saveFails}',
      ]);
    }
  });
}

Uint8List _document(int version) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'version': version,
      'provider': 'netease-cloud-music',
      'music_u': 'synthetic-u',
      'csrf': 'synthetic-c',
      if (version == 2) 'music_r_u': 'independent-r',
    }),
  ),
);

class _Vault implements CredentialVault {
  _Vault(Uint8List? bytes)
    : value = bytes == null ? null : Uint8List.fromList(bytes);
  Uint8List? value;
  Uint8List? lastRead;
  Completer<Uint8List?>? readGate;
  int reads = 0;
  int writes = 0;
  int deletes = 0;
  bool failWrites = false;
  @override
  Future<Uint8List?> read() async {
    reads++;
    lastRead = readGate != null
        ? await readGate!.future
        : value == null
        ? null
        : Uint8List.fromList(value!);
    return lastRead;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    writes++;
    if (failWrites) throw StateError('synthetic vault failure');
    value = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete() async {
    deletes++;
    value = null;
  }
}

class _Verification implements CredentialVerificationOperation {
  _Verification({this.onAuthenticated});
  final VoidCallback? onAuthenticated;
  final result = Completer<CredentialVerificationResult>();
  int runs = 0;
  bool cancelled = false;
  @override
  bool cancel() {
    cancelled = true;
    return true;
  }

  @override
  Future<CredentialVerificationResult> run() async {
    runs++;
    final outcome = await result.future;
    if (!cancelled && outcome == CredentialVerificationResult.authenticated) {
      onAuthenticated?.call();
    }
    return outcome;
  }
}

class _Broker extends ChangeNotifier implements OfficialWebLoginBroker {
  _Broker({this.candidate});
  final Uint8List? candidate;
  int starts = 0;
  Completer<bool>? cleanupGate;
  @override
  bool get isSupported => true;
  @override
  Listenable get presentationListenable => this;
  @override
  OfficialWebLoginPresentationStage get presentationStage =>
      OfficialWebLoginPresentationStage.idle;
  @override
  Widget? get activeView => null;
  @override
  Future<Uint8List?> authenticate() async {
    starts++;
    return candidate;
  }

  @override
  bool cancel() => true;
  @override
  Future<bool> clearWebsiteData() async =>
      cleanupGate == null ? true : await cleanupGate!.future;
}
