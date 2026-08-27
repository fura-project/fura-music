import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

void main() {
  test('maps the bounded Bridge identity into the local account model', () {
    final result = mapBridgeAccountSummaryLoad(
      const bridge.QqMusicAccountSummaryLoad(
        summary: bridge.QqMusicAccountSummary(
          displayName: 'Synthetic listener',
          avatarUri: 'https://example.invalid/avatar.jpg',
        ),
      ),
    );

    expect(result.failure, isNull);
    expect(result.summary?.displayName, 'Synthetic listener');
    expect(result.summary?.avatarUri, 'https://example.invalid/avatar.jpg');
  });

  test('maps every Bridge failure and rejects contradictory shapes', () {
    final expected = {
      bridge.QqMusicAccountSummaryFailure.coreUnavailable:
          AccountSummaryFailure.coreUnavailable,
      bridge.QqMusicAccountSummaryFailure.authenticationRequired:
          AccountSummaryFailure.authenticationRequired,
      bridge.QqMusicAccountSummaryFailure.credentialRejected:
          AccountSummaryFailure.credentialRejected,
      bridge.QqMusicAccountSummaryFailure.network:
          AccountSummaryFailure.network,
      bridge.QqMusicAccountSummaryFailure.serviceUnavailable:
          AccountSummaryFailure.serviceUnavailable,
      bridge.QqMusicAccountSummaryFailure.invalidResponse:
          AccountSummaryFailure.invalidResponse,
      bridge.QqMusicAccountSummaryFailure.replaced:
          AccountSummaryFailure.replaced,
      bridge.QqMusicAccountSummaryFailure.cancelled:
          AccountSummaryFailure.cancelled,
      bridge.QqMusicAccountSummaryFailure.alreadyRunning:
          AccountSummaryFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeAccountSummaryFailure(input), output);
    }

    expect(
      mapBridgeAccountSummaryLoad(
        const bridge.QqMusicAccountSummaryLoad(
          summary: bridge.QqMusicAccountSummary(displayName: 'conflict'),
          failure: bridge.QqMusicAccountSummaryFailure.network,
        ),
      ).failure,
      AccountSummaryFailure.invalidResponse,
    );
    expect(
      mapBridgeAccountSummaryLoad(
        const bridge.QqMusicAccountSummaryLoad(
          summary: bridge.QqMusicAccountSummary(displayName: '   '),
        ),
      ).failure,
      AccountSummaryFailure.invalidResponse,
    );
  });

  test(
    'forwards cancellation and cleans the vault only after rejection',
    () async {
      final operation = _ImmediateOperation(
        const AccountSummaryLoadResult(
          failure: AccountSummaryFailure.credentialRejected,
        ),
      );
      final vault = _FakeVault();
      final gateway = RustAccountSummaryGateway(
        credentialVault: vault,
        operationFactory: () => operation,
      );

      final load = gateway.beginLoad();
      expect(load.cancel(), isTrue);
      expect(operation.cancelCalls, 1);
      final result = await load.run();
      expect(result.failure, AccountSummaryFailure.credentialRejected);
      expect(vault.deleteCalls, 1);

      final transientVault = _FakeVault();
      final transient = RustAccountSummaryGateway(
        credentialVault: transientVault,
        operationFactory: () => _ImmediateOperation(
          const AccountSummaryLoadResult(
            failure: AccountSummaryFailure.network,
          ),
        ),
      );
      await transient.beginLoad().run();
      expect(transientVault.deleteCalls, 0);
    },
  );

  test(
    'reports secure-vault cleanup failure after credential rejection',
    () async {
      final vault = _FakeVault(
        deleteError: StateError('synthetic cleanup failure'),
      );
      final gateway = RustAccountSummaryGateway(
        credentialVault: vault,
        operationFactory: () => _ImmediateOperation(
          const AccountSummaryLoadResult(
            failure: AccountSummaryFailure.credentialRejected,
          ),
        ),
      );

      final result = await gateway.beginLoad().run();

      expect(
        result.failure,
        AccountSummaryFailure.credentialRejectedStorageCleanupFailed,
      );
      expect(vault.deleteCalls, 1);
    },
  );
}

class _ImmediateOperation implements AccountSummaryLoadOperation {
  _ImmediateOperation(this.result);

  final AccountSummaryLoadResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<AccountSummaryLoadResult> run() async => result;
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
