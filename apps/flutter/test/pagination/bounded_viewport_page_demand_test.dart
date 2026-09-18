import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';

void main() {
  testWidgets(
    'notification defers and coalesces demand before callback rebuilds layout',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final key = GlobalKey<_DemandHarnessState>();
      await tester.pumpWidget(
        MaterialApp(home: _DemandHarness(key: key, disableOnDemand: true)),
      );

      key.currentState!
        ..dispatch(delta: 40, extentAfter: 20)
        ..dispatch(delta: 80, extentAfter: 10)
        ..dispatch(delta: 120, extentAfter: 0);

      // ScrollNotification dispatch still belongs to this frame's layout and
      // notification phase. Business mutation starts only after that frame.
      expect(key.currentState!.demands, 0);
      expect(key.currentState!.enabled, isTrue);
      await tester.pump();
      expect(key.currentState!.demands, 1);
      expect(key.currentState!.enabled, isFalse);
      await tester.pump();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'loading enable toggle and zero-extent-growth append do not rearm approach',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final key = GlobalKey<_DemandHarnessState>();
      await tester.pumpWidget(
        MaterialApp(home: _DemandHarness(key: key, disableOnDemand: true)),
      );

      key.currentState!.dispatch(delta: 120, extentAfter: 0);
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.demands, 1);

      // Models an all-omitted, heavily deduplicated, or short Provider page:
      // loading finishes but the visible list extent does not grow.
      key.currentState!.setEnabled(true);
      await tester.pump();
      key.currentState!
        ..dispatch(delta: 20, extentAfter: 0)
        ..dispatch(delta: 20, extentAfter: 0);
      await tester.pump();
      expect(key.currentState!.demands, 1);

      // Only a real retreat grants another approach window.
      key.currentState!.dispatch(delta: -80, extentAfter: 300);
      expect(key.currentState!.retreats, 0);
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.retreats, 1);
      key.currentState!.dispatch(delta: 80, extentAfter: 0);
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.demands, 2);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'generation change cancels stale dispatch and explicitly rearms',
    (tester) async {
      final key = GlobalKey<_DemandHarnessState>();
      await tester.pumpWidget(
        MaterialApp(home: _DemandHarness(key: key, disableOnDemand: false)),
      );

      key.currentState!.dispatch(delta: 80, extentAfter: 0);
      key.currentState!.setGeneration(2);
      await tester.pump();
      expect(key.currentState!.demands, 0);

      key.currentState!.dispatch(delta: 80, extentAfter: 0);
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.demands, 1);

      key.currentState!.setGeneration(3);
      await tester.pump();
      key.currentState!.dispatch(delta: 80, extentAfter: 0);
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.demands, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving the threshold rearms without an upward scroll', (
    tester,
  ) async {
    final key = GlobalKey<_DemandHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _DemandHarness(key: key, disableOnDemand: false)),
    );

    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    await tester.pump();
    expect(key.currentState!.demands, 1);

    key.currentState!.dispatch(delta: 10, extentAfter: 1000);
    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    await tester.pump();
    expect(key.currentState!.demands, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels a recorded but undispatched demand', (
    tester,
  ) async {
    final key = GlobalKey<_DemandHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _DemandHarness(key: key, disableOnDemand: false)),
    );

    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    expect(key.currentState!.demands, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disable cancels pending dispatch without granting re-enable', (
    tester,
  ) async {
    final key = GlobalKey<_DemandHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _DemandHarness(key: key, disableOnDemand: false)),
    );

    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    key.currentState!.setEnabled(false);
    await tester.pump();
    expect(key.currentState!.demands, 0);

    key.currentState!.setEnabled(true);
    await tester.pump();
    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    await tester.pump();
    expect(key.currentState!.demands, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit retreat while disabled rearms the next approach', (
    tester,
  ) async {
    final key = GlobalKey<_DemandHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _DemandHarness(key: key, disableOnDemand: true)),
    );

    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    await tester.pump();
    await tester.pump();
    expect(key.currentState!.demands, 1);
    expect(key.currentState!.enabled, isFalse);

    // Temporary loading disable blocks callbacks, but it does not erase the
    // observed fact that the viewport actually retreated.
    key.currentState!.dispatch(delta: -80, extentAfter: 600);
    await tester.pump();
    expect(key.currentState!.retreats, 0);
    key.currentState!.setEnabled(true);
    await tester.pump();
    key.currentState!.dispatch(delta: 80, extentAfter: 0);
    await tester.pump();
    expect(key.currentState!.demands, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'semantics rapid fling hover and viewport resize stay frame-phase safe',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(420, 620);
      final key = GlobalKey<_DemandHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _DemandHarness(
            key: key,
            disableOnDemand: false,
            growOnDemand: true,
          ),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(80, 100));
      await mouse.moveTo(const Offset(120, 160));
      await tester.fling(find.byType(ListView), const Offset(0, -2400), 9000);
      await tester.pump();

      tester.view.physicalSize = const Size(760, 420);
      await tester.pump();
      await mouse.moveTo(const Offset(240, 180));
      await tester.fling(find.byType(ListView), const Offset(0, 900), 6000);
      await tester.pump();
      await tester.fling(find.byType(ListView), const Offset(0, -1800), 8000);
      await tester.pumpAndSettle();

      expect(key.currentState!.demands, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

class _DemandHarness extends StatefulWidget {
  const _DemandHarness({
    required super.key,
    required this.disableOnDemand,
    this.growOnDemand = false,
  });

  final bool disableOnDemand;
  final bool growOnDemand;

  @override
  State<_DemandHarness> createState() => _DemandHarnessState();
}

class _DemandHarnessState extends State<_DemandHarness> {
  late BuildContext _notificationContext;
  bool enabled = true;
  int generation = 1;
  int itemCount = 80;
  int demands = 0;
  int retreats = 0;

  void dispatch({required double delta, required double extentAfter}) {
    ScrollUpdateNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 4000,
        pixels: 4000 - extentAfter,
        viewportDimension: 240,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      ),
      context: _notificationContext,
      scrollDelta: delta,
    ).dispatch(_notificationContext);
    WidgetsBinding.instance.scheduleFrame();
  }

  void setEnabled(bool value) => setState(() => enabled = value);

  void setGeneration(int value) => setState(() {
    generation = value;
    enabled = true;
  });

  void _onDemand() {
    setState(() {
      demands += 1;
      if (widget.disableOnDemand) enabled = false;
      if (widget.growOnDemand) itemCount += 3;
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: BoundedViewportPageDemand(
      enabled: enabled,
      generation: generation,
      onDemand: _onDemand,
      onRetreat: () => setState(() => retreats += 1),
      child: Builder(
        builder: (context) {
          _notificationContext = context;
          return MouseRegion(
            child: ListView.builder(
              itemExtent: 44,
              itemCount: itemCount,
              itemBuilder: (_, index) =>
                  Semantics(label: 'Result $index', child: Text('Row $index')),
            ),
          );
        },
      ),
    ),
  );
}
