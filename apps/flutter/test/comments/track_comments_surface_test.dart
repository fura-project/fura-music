import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/comments/track_comments_surface.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  testWidgets('compact panel exposes failure retry content and close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closeCalls = 0;
    final gateway = _ScriptedGateway([
      const TrackCommentPageResult(failure: TrackCommentFailure.network),
      TrackCommentPageResult(
        total: 1,
        latestComments: [
          _comment(
            'one',
            'A long synthetic comment that wraps safely at compact width.',
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: Scaffold(
          body: TrackCommentsPanel(
            gateway: gateway,
            track: _track,
            onClose: () => closeCalls += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('track-comments-error')), findsOneWidget);
    expect(find.text('Couldn’t load comments'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('track-comments-retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('track-comments-content')),
      findsOneWidget,
    );
    expect(find.text('Newest'), findsOneWidget);
    expect(find.textContaining('wraps safely'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(gateway.requests, [(0, 20), (0, 20)]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('track-comments-close')));
    expect(closeCalls, 1);
  });

  testWidgets('empty response has a stable explicit state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.dark(),
        home: Scaffold(
          body: TrackCommentsPanel(
            gateway: _ScriptedGateway([const TrackCommentPageResult()]),
            track: _track,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('track-comments-empty')), findsOneWidget);
    expect(find.text('No comments yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:41001:0:syntheticMid:-',
  title: 'Synthetic Track',
  artistNames: ['Synthetic Artist'],
);

TrackCommentSummary _comment(String id, String content) => TrackCommentSummary(
  providerId: 'qq-music',
  opaqueId: 'comment:$id',
  authorDisplayName: 'Synthetic author with a long name',
  content: content,
  publishedAtUnixSeconds: 1700000000,
  praiseCount: 5,
);

class _ScriptedGateway implements TrackCommentGateway {
  _ScriptedGateway(this.results);

  final List<TrackCommentPageResult> results;
  final List<(int, int)> requests = [];
  int next = 0;

  @override
  TrackCommentPageLoadOperation beginLoad({
    required PlaylistTrackSummary track,
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return _ImmediateOperation(results[next++]);
  }
}

class _ImmediateOperation implements TrackCommentPageLoadOperation {
  const _ImmediateOperation(this.result);

  final TrackCommentPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackCommentPageResult> run() async => result;
}
