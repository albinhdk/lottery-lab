class EmbeddedBackendResult {
  /// Loopback base URL of the in-process server, or null when unavailable.
  final String? base;

  /// Human-readable reason when the embedded server could not start.
  final String? error;

  const EmbeddedBackendResult({this.base, this.error});

  bool get available => base != null;
}
