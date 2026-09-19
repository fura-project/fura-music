import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/recommended_playlists_page.dart';

void main() {
  test('Ranking grid follows product breakpoints and fills each row', () {
    const cases = <(double, int)>[
      (700, 1),
      (760, 2),
      (900, 2),
      (1000, 2),
      (1050, 3),
      (1180, 3),
    ];

    for (final (width, expectedColumns) in cases) {
      final metrics = discoverRankingGridMetrics(availableWidth: width);
      expect(metrics.columns, expectedColumns, reason: 'width=$width');
      expect(
        metrics.itemExtent * metrics.columns + 12 * (metrics.columns - 1),
        closeTo(width, 0.001),
        reason: 'width=$width',
      );
    }
  });
}
