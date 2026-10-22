/// Read-only projection for the control center. Native state is authoritative;
/// the host still owns writes, request serials and device reconciliation.
class VolumePresentation {
  double? level;
  bool muted = false;
  bool interacting = false;
  double? _pending;
  int _revision = 0;

  bool get needsReconciliation => _pending != null;
  int beginRead() => _revision;

  void completeRead(int token, double? value) {
    if (token != _revision ||
        value == null ||
        interacting ||
        _pending != null) {
      return;
    }
    level = value.clamp(0.0, 1.0);
    muted = false;
    _revision++;
  }

  void nativeState(double value, {required bool isMuted}) {
    _revision++;
    final next = isMuted ? 0.0 : value.clamp(0.0, 1.0);
    if (interacting) return;
    // A late acknowledgement for an older coalesced write must not rewind the
    // thumb. A bounded native read reconciles failures or clamped output levels.
    if (_pending != null && (next * 100).round() != (_pending! * 100).round()) {
      return;
    }
    level = next;
    muted = isMuted;
    _pending = null;
  }

  void beginInteraction() {
    interacting = true;
    _revision++;
  }

  void intent(double value) {
    level = value.clamp(0.0, 1.0);
    muted = false;
    _pending = level;
    _revision++;
  }

  void commit(double value) {
    intent(value);
    interacting = false;
  }

  void reconcile() {
    if (interacting) return;
    _pending = null;
    _revision++;
  }
}
