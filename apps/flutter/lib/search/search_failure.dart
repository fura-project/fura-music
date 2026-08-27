enum SearchFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  cancelled,
  alreadyRunning,
}

extension SearchFailurePolicy on SearchFailure {
  bool get isRetryable =>
      this == SearchFailure.coreUnavailable ||
      this == SearchFailure.network ||
      this == SearchFailure.serviceUnavailable ||
      this == SearchFailure.invalidResponse ||
      this == SearchFailure.alreadyRunning;
}
