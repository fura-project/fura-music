import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/pagination/raw_offset_page.dart';

void main() {
  test('visible rows never define raw continuation', () {
    expect(
      isValidRawOffsetPage(
        offset: 0,
        continuationOffset: 20,
        total: 40,
        hasMore: true,
        visibleCount: 19,
        omittedCount: 1,
      ),
      isTrue,
    );
    expect(
      isValidRawOffsetPage(
        offset: 20,
        continuationOffset: 40,
        total: 40,
        hasMore: false,
        visibleCount: 18,
        omittedCount: 0,
      ),
      isTrue,
      reason: 'deduplication may make visible + omitted smaller than raw',
    );
  });

  test('all-omitted raw page can advance within a bounded demand', () {
    expect(
      isValidRawOffsetPage(
        offset: 20,
        continuationOffset: 40,
        total: 60,
        hasMore: true,
        visibleCount: 0,
        omittedCount: 20,
      ),
      isTrue,
    );
  });

  test('more requires monotonic progress and bounded cursor', () {
    expect(
      isValidRawOffsetPage(
        offset: 20,
        continuationOffset: 20,
        total: 60,
        hasMore: true,
        visibleCount: 0,
        omittedCount: 0,
      ),
      isFalse,
    );
    expect(
      isValidRawOffsetPage(
        offset: maximumProviderOffset,
        continuationOffset: maximumProviderOffset + 1,
        hasMore: true,
        visibleCount: 0,
        omittedCount: 0,
      ),
      isFalse,
    );
  });

  test('terminal exact-total page cannot fabricate continuation', () {
    expect(
      isValidRawOffsetPage(
        offset: 20,
        continuationOffset: 39,
        total: 40,
        hasMore: false,
        visibleCount: 19,
        omittedCount: 0,
      ),
      isFalse,
    );
    expect(
      isValidRawOffsetPage(
        offset: 20,
        continuationOffset: 40,
        total: 40,
        hasMore: false,
        visibleCount: 19,
        omittedCount: 0,
      ),
      isTrue,
    );
  });
}
