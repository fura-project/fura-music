import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/comments.dart' as bridge;

void main() {
  test('maps a valid page and keeps returned collections immutable', () {
    final result = mapBridgeTrackCommentPage(
      bridge.QqMusicTrackCommentPageLoad(
        offset: 0,
        total: 2,
        hasMore: true,
        hotComments: [_bridgeComment('hot', 'Hot author', 'Hot content')],
        latestComments: [
          _bridgeComment('latest', 'Latest author', 'Latest content'),
        ],
      ),
    );

    expect(result.failure, isNull);
    expect(result.offset, 0);
    expect(result.total, 2);
    expect(result.hasMore, isTrue);
    expect(result.hotComments.single.opaqueId, 'comment:hot');
    expect(result.latestComments.single.content, 'Latest content');
    expect(() => result.hotComments.clear(), throwsUnsupportedError);
    expect(() => result.latestComments.clear(), throwsUnsupportedError);
  });

  test('maps every coarse Bridge failure', () {
    final expected = {
      bridge.QqMusicTrackCommentPageLoadFailure.coreUnavailable:
          TrackCommentFailure.coreUnavailable,
      bridge.QqMusicTrackCommentPageLoadFailure.network:
          TrackCommentFailure.network,
      bridge.QqMusicTrackCommentPageLoadFailure.serviceUnavailable:
          TrackCommentFailure.serviceUnavailable,
      bridge.QqMusicTrackCommentPageLoadFailure.invalidResponse:
          TrackCommentFailure.invalidResponse,
      bridge.QqMusicTrackCommentPageLoadFailure.cancelled:
          TrackCommentFailure.cancelled,
      bridge.QqMusicTrackCommentPageLoadFailure.alreadyRunning:
          TrackCommentFailure.alreadyRunning,
    };

    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeTrackCommentFailure(input), output);
    }
  });

  test('rejects conflicting malformed and impossible page envelopes', () {
    final valid = _bridgeComment('one', 'Author', 'Content');
    final malformed = [
      bridge.QqMusicTrackCommentPageLoad(
        offset: 1,
        total: 0,
        hasMore: false,
        hotComments: const [],
        latestComments: const [],
        failure: bridge.QqMusicTrackCommentPageLoadFailure.network,
      ),
      bridge.QqMusicTrackCommentPageLoad(
        offset: 1,
        total: 2,
        hasMore: false,
        hotComments: [valid],
        latestComments: [valid],
      ),
      bridge.QqMusicTrackCommentPageLoad(
        offset: 0,
        total: 1,
        hasMore: true,
        hotComments: const [],
        latestComments: [valid],
      ),
      bridge.QqMusicTrackCommentPageLoad(
        offset: 0,
        total: 1,
        hasMore: false,
        hotComments: const [],
        latestComments: [_bridgeComment('bad', '', 'Content')],
      ),
    ];

    for (final result in malformed) {
      expect(
        mapBridgeTrackCommentPage(result).failure,
        TrackCommentFailure.invalidResponse,
      );
    }
  });

  test('forwards exact opaque Track identity pagination and cancellation', () {
    late (String, String, int, int) request;
    final operation = _ImmediateOperation(
      const TrackCommentPageResult(failure: TrackCommentFailure.cancelled),
    );
    final gateway = RustTrackCommentGateway(
      operationFactory: (provider, opaqueTrackId, offset, size) {
        request = (provider, opaqueTrackId, offset, size);
        return operation;
      },
    );

    final begun = gateway.beginLoad(
      track: const PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:41001:0:opaqueMid:-',
        title: 'Synthetic Track',
        artistNames: ['Synthetic Artist'],
      ),
      offset: 20,
      size: 20,
    );
    expect(begun.cancel(), isTrue);
    expect(request, ('qq-music', 'track:41001:0:opaqueMid:-', 20, 20));
    expect(operation.cancelCalls, 1);
  });
}

bridge.TrackCommentSummary _bridgeComment(
  String id,
  String author,
  String content,
) => bridge.TrackCommentSummary(
  providerId: 'qq-music',
  opaqueId: 'comment:$id',
  authorDisplayName: author,
  content: content,
  publishedAtUnixSeconds: 1700000000,
  praiseCount: 7,
);

class _ImmediateOperation implements TrackCommentPageLoadOperation {
  _ImmediateOperation(this.result);

  final TrackCommentPageResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<TrackCommentPageResult> run() async => result;
}
