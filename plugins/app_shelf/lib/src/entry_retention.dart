// SPDX-License-Identifier: GPL-3.0-or-later

/// Bounded leases for visited rows. Eviction releases offscreen keep-alives;
/// it never removes a visible child or changes application data.
class EntryRetention {
  EntryRetention(this.limit) : assert(limit > 0);
  final int limit;
  final _entries = <String, EntryLease>{};
  int get length => _entries.length;

  EntryLease acquire(String key, void Function() onEvicted) {
    final duplicate = _entries.remove(key);
    duplicate?._evict();
    final lease = EntryLease._(key, onEvicted);
    _entries[key] = lease;
    while (_entries.length > limit) {
      _entries.remove(_entries.keys.first)!._evict();
    }
    return lease;
  }

  void release(EntryLease lease) {
    if (identical(_entries[lease.key], lease)) _entries.remove(lease.key);
    lease.retained = false;
  }
}

class EntryLease {
  EntryLease._(this.key, this._onEvicted);
  final String key;
  final void Function() _onEvicted;
  bool retained = true;
  void _evict() {
    retained = false;
    _onEvicted();
  }
}
