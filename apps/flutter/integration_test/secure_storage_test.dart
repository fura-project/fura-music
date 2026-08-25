import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native vault round-trips a disposable non-account marker', (
    _,
  ) async {
    final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final key = 'flutterustmusic.integration.vault.$timestamp.$nonce';
    final marker = 'non-account integration marker $timestamp $nonce';
    final store = FlutterSecureStringStore();

    try {
      expect(await store.read(key: key), isNull, reason: 'test-key collision');
      await store.write(key: key, value: marker);
      expect(await store.read(key: key), marker);
      await store.delete(key: key);
      expect(await store.read(key: key), isNull);
    } finally {
      await store.delete(key: key);
      expect(
        await store.read(key: key),
        isNull,
        reason: 'disposable secure-storage marker must not remain',
      );
    }
  }, skip: kIsWeb || !(Platform.isLinux || Platform.isAndroid));
}
