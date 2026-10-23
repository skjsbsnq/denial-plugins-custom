/// A dispatch acknowledgement is not a window-ready event. Callers supply IDs
/// for this application from the host's shared, unfiltered window snapshot.
class ApplicationLaunchWait {
  static const timeout = Duration(seconds: 30);

  int request = 0;
  bool dispatching = false;
  bool waitingForWindow = false;
  Set<int> _existing = {};

  bool get busy => dispatching || waitingForWindow;

  int? begin(Iterable<int> existingWindowIds) {
    if (busy) return null;
    _existing = existingWindowIds.toSet();
    dispatching = true;
    waitingForWindow = true;
    return ++request;
  }

  /// Returns false for late replies after a window, timeout or newer request.
  bool dispatched(int token, {required bool started}) {
    if (token != request || !dispatching) return false;
    dispatching = false;
    if (!started) waitingForWindow = false;
    return true;
  }

  bool observeWindows(Iterable<int> applicationWindowIds) {
    if (!waitingForWindow ||
        !applicationWindowIds.any((id) => !_existing.contains(id))) {
      return false;
    }
    waitingForWindow = false;
    dispatching = false;
    return true;
  }

  bool expire(int token) {
    if (token != request || !busy) return false;
    waitingForWindow = false;
    dispatching = false;
    return true;
  }
}
