import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/src/rust/api/search.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

const _liveTestsEnabled = bool.fromEnvironment('QQMUSIC_LIVE_TESTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('loads one anonymous QQ Music search page over Android HTTPS', (
    _,
  ) async {
    final result = await beginQqMusicTrackSearchPageLoad(
      query: '周杰伦',
      page: 1,
      size: 1,
    ).run();

    expect(
      result.failure,
      isNull,
      reason:
          'Android must initialize its rustls platform verifier before '
          'the first QQ Music HTTPS request.',
    );
    expect(result.items, isNotEmpty);
  }, skip: !Platform.isAndroid || !_liveTestsEnabled);
}
