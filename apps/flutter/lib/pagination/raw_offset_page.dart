const int maximumProviderOffset = 0xffffffff;

/// Validates one provider-owned raw-offset window.
///
/// [visibleCount] may be smaller than the raw window after row omission or
/// presentation-side identity deduplication. The continuation is therefore
/// validated as an independent upstream fact and is never derived from the
/// number of rows visible to Flutter.
bool isValidRawOffsetPage({
  required int offset,
  required int continuationOffset,
  required bool hasMore,
  required int visibleCount,
  required int omittedCount,
  int? total,
  bool terminalMustReachTotal = true,
}) {
  if (offset < 0 ||
      continuationOffset < offset ||
      continuationOffset > maximumProviderOffset ||
      visibleCount < 0 ||
      omittedCount < 0) {
    return false;
  }
  final consumedCount = continuationOffset - offset;
  if (visibleCount + omittedCount > consumedCount) return false;

  if (total case final exactTotal?) {
    if (exactTotal < 0 ||
        exactTotal > maximumProviderOffset ||
        continuationOffset > exactTotal) {
      return false;
    }
    if (hasMore) {
      return continuationOffset > offset && continuationOffset < exactTotal;
    }
    return !terminalMustReachTotal || continuationOffset == exactTotal;
  }

  return !hasMore || continuationOffset > offset;
}
