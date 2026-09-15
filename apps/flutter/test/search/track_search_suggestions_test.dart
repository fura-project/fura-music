import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_suggestions.dart';

void main() {
  testWidgets('raw query stays first while derived suggestions are bounded', (
    tester,
  ) async {
    final gateway = _SuggestionGateway([
      _immediateResult([
        _track('query'),
        _track('Alpha', artist: 'Artist A'),
        _track('alpha', artist: 'Duplicate'),
        _track('Beta'),
        _track('Gamma'),
        _track('Delta'),
        _track('Epsilon'),
        _track('Zeta'),
        _track('Ignored seventh'),
      ]),
    ]);
    final controller = TrackSearchSuggestionController(gateway);
    addTearDown(controller.dispose);

    controller.updateQuery('  query  ');
    expect(controller.visible, isTrue);
    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.query, 'query');
    expect(controller.entries.single.raw, isTrue);
    await tester.pump(const Duration(milliseconds: 319));
    expect(gateway.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(gateway.requests, [('query', 1, 8)]);
    expect(controller.entries, hasLength(7));
    expect(controller.entries.first.query, 'query');
    expect(controller.entries.skip(1).map((entry) => entry.query), [
      'Alpha',
      'Beta',
      'Gamma',
      'Delta',
      'Epsilon',
      'Zeta',
    ]);
    expect(controller.entries[1].detail, 'Artist A');
  });

  testWidgets('replacement query cancels and rejects stale candidates', (
    tester,
  ) async {
    final oldOperation = _ControlledSuggestionOperation();
    final newOperation = _ControlledSuggestionOperation();
    final gateway = _SuggestionGateway([oldOperation, newOperation]);
    final controller = TrackSearchSuggestionController(gateway);
    addTearDown(controller.dispose);

    controller.updateQuery('old');
    await tester.pump(const Duration(milliseconds: 320));
    expect(gateway.requests, [('old', 1, 8)]);
    controller.moveHighlight(1);
    expect(controller.highlightedQuery, 'old');

    controller.updateQuery('new');
    expect(oldOperation.cancelled, isTrue);
    expect(controller.highlightedIndex, isNull);
    expect(controller.entries.map((entry) => entry.query), ['new']);
    await tester.pump(const Duration(milliseconds: 320));
    expect(gateway.requests.last, ('new', 1, 8));

    oldOperation.complete(_result([_track('Stale result')]));
    await tester.pump();
    expect(controller.entries.map((entry) => entry.query), ['new']);
    newOperation.complete(_result([_track('Fresh result')]));
    await tester.pump();
    expect(controller.entries.map((entry) => entry.query), [
      'new',
      'Fresh result',
    ]);
  });

  testWidgets('highlight wraps, resets on text, and clears on dismissal', (
    tester,
  ) async {
    final controller = TrackSearchSuggestionController(
      _SuggestionGateway([
        _immediateResult([_track('Derived')]),
        _immediateResult([_track('Replacement')]),
      ]),
    );
    addTearDown(controller.dispose);

    controller.updateQuery('raw');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(controller.moveHighlight(-1), isTrue);
    expect(controller.highlightedQuery, 'Derived');
    expect(controller.moveHighlight(1), isTrue);
    expect(controller.highlightedQuery, 'raw');

    controller.updateQuery('changed');
    expect(controller.highlightedIndex, isNull);
    expect(controller.entries.map((entry) => entry.query), ['changed']);
    controller.dismiss();
    expect(controller.visible, isFalse);
    expect(controller.highlightedQuery, isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.entries.map((entry) => entry.query), ['changed']);
  });
}

PlaylistTrackSummary _track(String title, {String artist = ''}) =>
    PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:$title',
      title: title,
      artistNames: artist.isEmpty ? const [] : [artist],
    );

TrackSearchPageResult _result(List<PlaylistTrackSummary> tracks) =>
    TrackSearchPageResult(
      page: 1,
      total: tracks.length,
      items: tracks.map((track) => TrackSearchItem(track: track)).toList(),
    );

TrackSearchPageLoadOperation _immediateResult(
  List<PlaylistTrackSummary> tracks,
) => _ImmediateSuggestionOperation(_result(tracks));

class _SuggestionGateway implements TrackSearchGateway {
  _SuggestionGateway(this.operations);

  final List<TrackSearchPageLoadOperation> operations;
  final List<(String, int, int)> requests = [];

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return operations[requests.length - 1];
  }
}

class _ImmediateSuggestionOperation implements TrackSearchPageLoadOperation {
  const _ImmediateSuggestionOperation(this.result);

  final TrackSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackSearchPageResult> run() async => result;
}

class _ControlledSuggestionOperation implements TrackSearchPageLoadOperation {
  final Completer<TrackSearchPageResult> _result = Completer();
  bool cancelled = false;

  void complete(TrackSearchPageResult result) => _result.complete(result);

  @override
  bool cancel() => cancelled = true;

  @override
  Future<TrackSearchPageResult> run() => _result.future;
}
