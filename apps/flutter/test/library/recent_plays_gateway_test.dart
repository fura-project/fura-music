import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';

void main() {
  test('forwards paging without introducing playlist identity', () async {
    final operation = _Operation(
      const PlaylistTrackPageResult(
        offset: 100,
        nextOffset: 101,
        total: 102,
        totalIsExact: false,
        hasMore: true,
      ),
    );
    late (int, int) request;
    final gateway = RustRecentPlaysGateway(
      credentialVault: _Vault(),
      operationFactory: (offset, size) {
        request = (offset, size);
        return operation;
      },
    );

    final result = await gateway.beginLoad(offset: 100, size: 100).run();

    expect(request, (100, 100));
    expect(result.offset, 100);
    expect(result.nextOffset, 101);
    expect(result.totalIsExact, isFalse);
    expect(result.hasMore, isTrue);
  });

  test('credential rejection clears persisted account material', () async {
    final vault = _Vault();
    final gateway = RustRecentPlaysGateway(
      credentialVault: vault,
      operationFactory: (_, _) => _Operation(
        const PlaylistTrackPageResult(
          failure: UserLibraryFailure.credentialRejected,
        ),
      ),
    );

    final result = await gateway.beginLoad(offset: 0, size: 100).run();

    expect(result.failure, UserLibraryFailure.credentialRejected);
    expect(vault.deleteCalls, 1);
  });

  test('non-auth failures retain persisted account material', () async {
    final vault = _Vault();
    final gateway = RustRecentPlaysGateway(
      credentialVault: vault,
      operationFactory: (_, _) => _Operation(
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
      ),
    );

    await gateway.beginLoad(offset: 0, size: 100).run();

    expect(vault.deleteCalls, 0);
  });
}

class _Operation implements PlaylistTrackPageLoadOperation {
  _Operation(this.result);

  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => result;
}

class _Vault implements CredentialVault {
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
