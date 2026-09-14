import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/netease_external_login.dart';

void main() {
  const valid =
      'https://music.163.com/st/platform/scanlogin?'
      'codekey=synthetic-key&chainId=synthetic-chain&'
      'hdw_device=web&hdw_appid=web&hitExp=1';

  test('accepts only the exact official QR confirmation route', () {
    expect(isAllowedNeteaseQrConfirmationUri(Uri.parse(valid)), isTrue);
    expect(
      isAllowedNeteaseQrConfirmationUri(
        Uri.parse(valid.replaceFirst('https://', 'http://')),
      ),
      isFalse,
    );
    expect(
      isAllowedNeteaseQrConfirmationUri(
        Uri.parse(
          valid.replaceFirst('music.163.com', 'music.163.com.evil.test'),
        ),
      ),
      isFalse,
    );
    expect(
      isAllowedNeteaseQrConfirmationUri(
        Uri.parse(valid.replaceFirst('music.163.com', 'music.163.com:444')),
      ),
      isFalse,
    );
    expect(
      isAllowedNeteaseQrConfirmationUri(
        Uri.parse(valid.replaceFirst('codekey=', 'unexpected=1&codekey=')),
      ),
      isFalse,
    );
    expect(
      isAllowedNeteaseQrConfirmationUri(
        Uri.parse(valid.replaceFirst('synthetic-key', 'unsafe%2Fkey')),
      ),
      isFalse,
    );
  });
}
