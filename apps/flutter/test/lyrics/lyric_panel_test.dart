import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';

void main() {
  testWidgets('renders canonical content and real word progress', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    int? seekPosition;
    final controller = LyricController(
      _ScriptedGateway([_ImmediateOperation(_success())]),
    );
    await controller.load(_track);
    controller.updatePositionMs(1250);

    await _pumpPanel(
      tester,
      controller,
      canSeek: () => true,
      onSeek: (positionMs) async => seekPosition = positionMs,
    );

    expect(find.byKey(const ValueKey('lyrics-content')), findsOneWidget);
    expect(find.text('timed '), findsOneWidget);
    expect(find.text('line'), findsOneWidget);
    expect(find.text('定时行'), findsOneWidget);
    expect(find.text('ding shi hang'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('lyrics-word-0-0'))).value,
      '50% complete',
    );
    final line = find.byKey(const ValueKey('lyrics-line-0'));
    expect(
      tester
          .getSemantics(line)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(line);
    expect(seekPosition, 1000);
    semantics.dispose();
    controller.dispose();
  });

  testWidgets('keeps a long translation fully visible on a narrow display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = LyricController(
      _ScriptedGateway([_ImmediateOperation(_longTranslation())]),
    );
    await controller.load(_track);
    controller.updatePositionMs(1250);

    await _pumpPanel(tester, controller);
    await tester.pumpAndSettle();

    final translation = find.byKey(const ValueKey('lyrics-translation-0'));
    final text = tester.widget<Text>(translation);
    expect(text.softWrap, isTrue);
    expect(text.maxLines, isNull);
    expect(text.overflow, TextOverflow.visible);
    expect(tester.getSize(translation).height, greaterThan(40));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('lyrics-line-0')))
          .contains(tester.getRect(translation).bottomRight),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets(
    'highlights the displayed lyric without inserting mismatched segment text',
    (tester) async {
      final controller = LyricController(
        _ScriptedGateway([_ImmediateOperation(_mismatchedSegments())]),
      );
      await controller.load(_track);
      controller.updatePositionMs(1250);

      await _pumpPanel(tester, controller);
      await tester.pumpAndSettle();

      expect(find.text('displayed original'), findsOneWidget);
      expect(find.text('完整翻译'), findsOneWidget);
      expect(find.text('mismatched timed text'), findsNothing);
      expect(find.byKey(const ValueKey('lyrics-line-0')), findsOneWidget);

      controller.dispose();
    },
  );

  testWidgets(
    'follows active lines until manual scrolling and resets per track',
    (tester) async {
      tester.view.physicalSize = const Size(400, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = LyricController(
        _ScriptedGateway([
          _ImmediateOperation(_longLyrics()),
          _ImmediateOperation(_longLyrics(prefix: 'replacement')),
        ]),
      );
      await controller.load(_track);
      controller.updatePositionMs(250);
      await _pumpPanel(tester, controller);
      await tester.pumpAndSettle();

      controller.updatePositionMs(8250);
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('lyrics-line-list'));
      final lineEight = find.byKey(const ValueKey('lyrics-line-8'));
      expect(lineEight, findsOneWidget);
      expect(tester.getRect(lineEight).overlaps(tester.getRect(list)), isTrue);
      expect(_scrollOffset(tester, list), greaterThan(0));

      await tester.drag(list, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lyrics-resume-following')),
        findsOneWidget,
      );
      final pausedOffset = _scrollOffset(tester, list);

      controller.updatePositionMs(9250);
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester, list), closeTo(pausedOffset, 0.1));

      await tester.tap(find.byKey(const ValueKey('lyrics-resume-following')));
      await tester.pumpAndSettle();
      final lineNine = find.byKey(const ValueKey('lyrics-line-9'));
      expect(lineNine, findsOneWidget);
      expect(tester.getRect(lineNine).overlaps(tester.getRect(list)), isTrue);
      expect(
        find.byKey(const ValueKey('lyrics-resume-following')),
        findsNothing,
      );

      await tester.drag(list, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lyrics-resume-following')),
        findsOneWidget,
      );
      await controller.load(_replacementTrack);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lyrics-resume-following')),
        findsNothing,
      );
      final firstReplacementLine = find.byKey(const ValueKey('lyrics-line-0'));
      expect(firstReplacementLine, findsOneWidget);
      expect(
        tester.getRect(firstReplacementLine).overlaps(tester.getRect(list)),
        isTrue,
      );

      controller.dispose();
    },
  );

  testWidgets('shows loading then an honest unavailable state', (tester) async {
    final semantics = tester.ensureSemantics();
    final pending = _PendingOperation();
    final controller = LyricController(_ScriptedGateway([pending]));
    final load = controller.load(_track);

    await _pumpPanel(tester, controller);
    expect(find.byKey(const ValueKey('lyrics-loading')), findsOneWidget);

    pending.complete(const LyricLoadResult(failure: LyricFailure.unavailable));
    await load;
    await tester.pump();
    expect(find.byKey(const ValueKey('lyrics-unavailable')), findsOneWidget);
    expect(find.text('No synchronized lyrics'), findsOneWidget);
    final unavailableSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('No synchronized lyrics')),
    );
    expect(unavailableSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(
      unavailableSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );

    semantics.dispose();
    controller.dispose();
  });

  testWidgets('retries a transient failure through the same controller', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _ScriptedGateway([
      const _ImmediateOperation(LyricLoadResult(failure: LyricFailure.network)),
      _ImmediateOperation(_success()),
    ]);
    final controller = LyricController(gateway);
    await controller.load(_track);

    await _pumpPanel(tester, controller);
    expect(find.byKey(const ValueKey('lyrics-error')), findsOneWidget);
    expect(find.text('Couldn’t reach QQ Music'), findsOneWidget);
    final failureSemantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Couldn’t reach QQ Music')),
    );
    expect(failureSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(
      failureSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('lyrics-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyrics-content')), findsOneWidget);
    expect(gateway.requests, [
      ('qq-music', 'track:fixture'),
      ('qq-music', 'track:fixture'),
    ]);

    semantics.dispose();
    controller.dispose();
  });

  testWidgets('offers the existing sign-in action for an account state', (
    tester,
  ) async {
    var signInAgainCalls = 0;
    final controller = LyricController(
      _ScriptedGateway([
        const _ImmediateOperation(
          LyricLoadResult(failure: LyricFailure.authenticationRequired),
        ),
      ]),
    );
    await controller.load(_track);

    await _pumpPanel(
      tester,
      controller,
      onSignInAgain: () => signInAgainCalls += 1,
    );
    expect(
      find.byKey(const ValueKey('lyrics-authentication-required')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('lyrics-sign-in-again')));
    expect(signInAgainCalls, 1);

    controller.dispose();
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  LyricController controller, {
  VoidCallback? onSignInAgain,
  bool Function()? canSeek,
  Future<void> Function(int positionMs)? onSeek,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: LyricPanel(
        controller: controller,
        onClose: () {},
        onSignInAgain: onSignInAgain ?? () {},
        canSeek: canSeek,
        onSeek: onSeek,
      ),
    ),
  ),
);

const _track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:fixture',
  title: 'Fixture track',
  artistNames: ['Fixture artist'],
);

const _replacementTrack = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:replacement',
  title: 'Replacement fixture track',
  artistNames: ['Fixture artist'],
);

double _scrollOffset(WidgetTester tester, Finder list) => tester
    .state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    )
    .position
    .pixels;

LyricLoadResult _success() => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    SynchronizedLyricLine(
      text: 'timed line',
      startMs: 1000,
      durationMs: 1500,
      translation: '定时行',
      romanization: 'ding shi hang',
      segments: const [
        TimedLyricSegment(text: 'timed ', startMs: 1000, durationMs: 500),
        TimedLyricSegment(text: 'line', startMs: 1500, durationMs: 500),
      ],
    ),
  ]),
);

LyricLoadResult _longTranslation() => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    SynchronizedLyricLine(
      text: 'A deliberately long original lyric line',
      startMs: 1000,
      durationMs: 2500,
      translation:
          '这是一条用于验证窄屏和放大字体时仍能完整换行显示，'
          '不会被固定行数或溢出策略截断的长翻译。',
      romanization: 'A complete romanization remains available as well.',
      segments: const [],
    ),
  ]),
);

LyricLoadResult _mismatchedSegments() => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    SynchronizedLyricLine(
      text: 'displayed original',
      startMs: 1000,
      durationMs: 500,
      translation: '完整翻译',
      segments: const [
        TimedLyricSegment(
          text: 'mismatched timed text',
          startMs: 1000,
          durationMs: 500,
        ),
      ],
    ),
  ]),
);

LyricLoadResult _longLyrics({String prefix = 'line'}) => LyricLoadResult(
  lyrics: SynchronizedLyrics([
    for (var index = 0; index < 12; index += 1)
      SynchronizedLyricLine(
        text: '$prefix $index',
        startMs: index * 1000,
        durationMs: 1000,
        segments: const [],
      ),
  ]),
);

class _ScriptedGateway implements LyricGateway {
  _ScriptedGateway(this.operations);

  final List<LyricLoadOperation> operations;
  final List<(String, String)> requests = [];
  int _next = 0;

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) {
    requests.add((providerId, opaqueTrackId));
    return operations[_next++];
  }
}

class _ImmediateOperation implements LyricLoadOperation {
  const _ImmediateOperation(this.result);

  final LyricLoadResult result;

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async => result;
}

class _PendingOperation implements LyricLoadOperation {
  final Completer<LyricLoadResult> _result = Completer();

  void complete(LyricLoadResult result) => _result.complete(result);

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() => _result.future;
}
