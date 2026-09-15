import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/partial_results_notice.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';

void main() {
  testWidgets('localizes the shared warning and announces each result once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var revision = 1;

    Widget app(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              PartialResultsNotice(omittedCount: 2, resultRevision: revision),
              TextButton(
                onPressed: () => setState(() => revision += 1),
                child: const Text('update'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(const Locale('en')));
    final notice = find.byKey(const ValueKey('partial-results-semantics'));
    expect(
      tester
          .getSemantics(notice)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.textContaining('2 unsafe items were skipped'), findsOneWidget);
    await tester.pump();
    expect(
      tester
          .getSemantics(notice)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );

    await tester.tap(find.text('update'));
    await tester.pump();
    expect(
      tester
          .getSemantics(notice)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    await tester.pump();
    expect(
      tester
          .getSemantics(notice)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );

    await tester.pumpWidget(app(const Locale('zh')));
    expect(find.text('部分内容无法安全显示，已跳过 2 项，其余结果不受影响。'), findsOneWidget);
    semantics.dispose();
  });
}
