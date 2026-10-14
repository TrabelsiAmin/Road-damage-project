/// Token for cooperative cancellation of sync operations.
class SyncCancelToken {
  bool _cancelled = false;

  /// Returns true if cancellation has been requested.
  bool get isCancelled => _cancelled;

  /// Requests cancellation of the ongoing sync process.
  void cancel() {
    _cancelled = true;
  }

  /// Throws [SyncCancelledException] if cancellation has been requested.
  void throwIfCancelled() {
    if (_cancelled) {
      throw const SyncCancelledException();
    }
  }
}

/// Thrown when a sync operation is cancelled by the user.
class SyncCancelledException implements Exception {
  const SyncCancelledException([this.message = 'Sync cancelled by user']);
  final String message;

  @override
  String toString() => message;
}
