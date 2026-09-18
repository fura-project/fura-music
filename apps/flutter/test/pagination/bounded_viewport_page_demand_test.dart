import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/pagination/bounded_viewport_page_demand.dart';

void main() {
  testWidgets('one near-end approach emits one bounded demand', (tester) async {
    final pending = Completer<void>();
    var demands = 0;
    var retreats = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 240,
          child: BoundedViewportPageDemand(
            onDemand: () {
              demands += 1;
              return pending.future;
            },
            onRetreat: () => retreats += 1,
            child: ListView.builder(
              itemExtent: 48,
              itemCount: 40,
              itemBuilder: (_, index) => Text('Row $index'),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    expect(demands, 1);

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    expect(retreats, greaterThan(0));
    pending.complete();
  });

  testWidgets('generation change rearms the next bounded demand', (
    tester,
  ) async {
    var generation = 1;
    var demands = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SizedBox(
              height: 240,
              child: BoundedViewportPageDemand(
                generation: generation,
                onDemand: () => demands += 1,
                child: ListView.builder(
                  itemExtent: 48,
                  itemCount: 40,
                  itemBuilder: (_, index) => Text('Row $index'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pump();
    expect(demands, 1);
    rebuild(() => generation = 2);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    expect(demands, 2);
  });
}
