import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_controller.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_scroll_prefetch.dart';

void main() {
  group('viewport prediction', () {
    int predict(
      PlaylistPrefetchPolicy policy, {
      double delta = 1,
      double remaining = 2800,
      Duration latency = const Duration(milliseconds: 300),
      int loaded = 100,
    }) => policy.targetTrackCount(
      loadedCount: loaded,
      extentAfter: remaining,
      contentExtent: loaded * 70,
      scrollDelta: delta,
      sampleTime: Duration.zero,
      pageLatency: latency,
    );

    test(
      'ordinary scrolling starts half a page before the loaded boundary',
      () {
        expect(predict(PlaylistPrefetchPolicy()), 110);
        expect(predict(PlaylistPrefetchPolicy(), remaining: 4900), 80);
      },
    );

    test('fast scrolling expands lookahead but caps it at two pages', () {
      expect(predict(PlaylistPrefetchPolicy(), delta: 1000), 260);
    });

    test(
      'smaller paged collections can reuse the policy without overfetching',
      () {
        final target = PlaylistPrefetchPolicy().targetTrackCount(
          loadedCount: 20,
          extentAfter: 200,
          contentExtent: 20 * 56,
          scrollDelta: 1000,
          sampleTime: Duration.zero,
          pageLatency: const Duration(milliseconds: 350),
          pageSize: 10,
        );

        expect(target, lessThanOrEqualTo(40));
        expect(target, greaterThan(20));
      },
    );

    test('the same speed prefetches earlier when page latency increases', () {
      final fastNetwork = predict(PlaylistPrefetchPolicy(), delta: 100);
      final slowNetwork = predict(
        PlaylistPrefetchPolicy(),
        delta: 100,
        latency: const Duration(seconds: 2),
      );
      expect(slowNetwork, greaterThan(fastNetwork));
      expect(slowNetwork, lessThanOrEqualTo(260));
    });

    test('upward scrolling and a fresh gesture reset velocity', () {
      final policy = PlaylistPrefetchPolicy();
      expect(predict(policy, delta: 1000), 260);
      expect(predict(policy, delta: -100), 100);
      expect(predict(policy), 110);
      predict(policy, delta: 1000);
      policy.reset();
      expect(predict(policy), 110);
    });

    test('append preserves the absolute viewport horizon instead of chasing the tail', () {
      expect(predict(PlaylistPrefetchPolicy()), 110);
      // Another 100 rows arrive while the viewport remains at the same place.
      expect(
        predict(PlaylistPrefetchPolicy(), loaded: 200, remaining: 9800),
        110,
      );
      expect(predict(PlaylistPrefetchPolicy(), loaded: 0), 0);
    });
  });

  testWidgets(
    'semantics rapid scroll defers append and upward scrolling reuses rows',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final gateway = _Gateway();
      final controller = PlaylistDetailController(
        _playlist,
        gateway,
        loadAllPageInterval: Duration.zero,
      );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      addTearDown(controller.dispose);
      final initial = controller.load();
      gateway.complete(0, 0);
      await initial;
      var outerNotifications = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  outerNotifications++;
                  return false;
                },
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, _) => PlaylistScrollPrefetch(
                    controller: controller,
                    child: ListView.builder(
                      controller: scroll,
                      itemExtent: 70,
                      itemCount: controller.tracks.length,
                      itemBuilder: (_, index) => Text('Row $index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(gateway.offsets, [0]); // Mount is not a whole-playlist prefetch.
      scroll.jumpTo(2200);
      scroll.jumpTo(2500);
      scroll.jumpTo(2800);
      expect(
        gateway.offsets,
        [0],
        reason: 'ScrollNotification must not start a notifying append inline.',
      );
      await tester.pump();
      expect(scroll.position.extentAfter, greaterThan(720));
      expect(gateway.offsets, [0, 100]);
      expect(
        outerNotifications,
        greaterThan(0),
      ); // Header listeners still receive it.
      scroll.jumpTo(1400);
      await tester.pump();
      gateway.complete(1, 100);
      await tester.pumpAndSettle();
      expect(controller.tracks, hasLength(200));
      expect(scroll.offset, 1400);
      expect(gateway.offsets, [0, 100]); // Pending second page was withdrawn.
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Row 0'), findsOneWidget);
      expect(gateway.offsets, [0, 100]);
      expect(
        find.text('Row 199'),
        findsNothing,
      ); // Rows remain lazy, not all mounted.
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'upward scroll disable replacement and dispose invalidate pending dispatch',
    (tester) async {
      final firstGateway = _Gateway();
      final first = PlaylistDetailController(_playlist, firstGateway);
      final secondGateway = _Gateway();
      final second = PlaylistDetailController(_playlist, secondGateway);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final firstLoad = first.load();
      firstGateway.complete(0, 0);
      await firstLoad;
      final secondLoad = second.load();
      secondGateway.complete(0, 0);
      await secondLoad;
      final key = GlobalKey<_PrefetchHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _PrefetchHarness(key: key, controller: first),
        ),
      );

      key.currentState!.dispatch(1000);
      key.currentState!.dispatch(-100);
      await tester.pump();
      expect(firstGateway.offsets, [0]);

      key.currentState!.dispatch(1000);
      key.currentState!.setEnabled(false);
      await tester.pump();
      expect(firstGateway.offsets, [0]);

      key.currentState!
        ..setEnabled(true)
        ..setController(second);
      await tester.pump();
      key.currentState!.dispatch(1000);
      key.currentState!.setController(first);
      await tester.pump();
      expect(firstGateway.offsets, [0]);
      expect(secondGateway.offsets, [0]);

      key.currentState!.dispatch(1000);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(firstGateway.offsets, [0]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filtered or inactive lists do not create browse requests', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = PlaylistDetailController(_playlist, gateway);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    addTearDown(controller.dispose);
    final initial = controller.load();
    gateway.complete(0, 0);
    await initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaylistScrollPrefetch(
            controller: controller,
            enabled: false,
            child: ListView.builder(
              controller: scroll,
              itemExtent: 70,
              itemCount: 100,
              itemBuilder: (_, index) => Text('Row $index'),
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(gateway.offsets, [0]);
  });
}

class _PrefetchHarness extends StatefulWidget {
  const _PrefetchHarness({required super.key, required this.controller});

  final PlaylistDetailController controller;

  @override
  State<_PrefetchHarness> createState() => _PrefetchHarnessState();
}

class _PrefetchHarnessState extends State<_PrefetchHarness> {
  late BuildContext _notificationContext;
  late PlaylistDetailController controller;
  bool enabled = true;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
  }

  void dispatch(double delta) {
    ScrollUpdateNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 7000,
        pixels: 5000,
        viewportDimension: 400,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      ),
      context: _notificationContext,
      scrollDelta: delta,
    ).dispatch(_notificationContext);
    WidgetsBinding.instance.scheduleFrame();
  }

  void setEnabled(bool value) => setState(() => enabled = value);

  void setController(PlaylistDetailController value) =>
      setState(() => controller = value);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 400,
    child: PlaylistScrollPrefetch(
      controller: controller,
      enabled: enabled,
      child: Builder(
        builder: (context) {
          _notificationContext = context;
          return ListView.builder(
            itemExtent: 70,
            itemCount: controller.tracks.length,
            itemBuilder: (_, index) => Text('Row $index'),
          );
        },
      ),
    ),
  );
}

const _playlist = UserPlaylistSummary(
  providerId: 'synthetic',
  opaqueId: 'prefetch-fixture',
  title: 'Prefetch fixture',
);

class _Gateway implements PlaylistDetailGateway {
  final offsets = <int>[];
  final results = <Completer<PlaylistTrackPageResult>>[];

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    offsets.add(offset);
    final result = Completer<PlaylistTrackPageResult>();
    results.add(result);
    return _Operation(result.future);
  }

  void complete(int request, int offset) => results[request].complete(
    PlaylistTrackPageResult(
      offset: offset,
      nextOffset: offset + 100,
      total: 1000,
      hasMore: offset + 100 < 1000,
      tracks: List.generate(
        100,
        (index) => PlaylistTrackSummary(
          providerId: 'synthetic',
          opaqueId: 'track:${offset + index}',
          title: 'Row ${offset + index}',
          artistNames: const [],
        ),
      ),
    ),
  );
}

class _Operation implements PlaylistTrackPageLoadOperation {
  _Operation(this.result);
  final Future<PlaylistTrackPageResult> result;
  @override
  Future<PlaylistTrackPageResult> run() => result;
  @override
  bool cancel() => true;
}
