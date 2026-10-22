class NetworkCounters {
  const NetworkCounters({required this.received, required this.transmitted});
  final int received;
  final int transmitted;
}

class NetworkSpeed {
  const NetworkSpeed({required this.download, required this.upload});
  final double download;
  final double upload;
}

/// Linux interface counters. Malformed records and loopback never contribute.
Map<String, NetworkCounters> parseNetworkCounters(String content) {
  final result = <String, NetworkCounters>{};
  for (final line in content.split('\n')) {
    final separator = line.lastIndexOf(':');
    if (separator < 0) continue;
    final name = line.substring(0, separator).trim();
    if (name.isEmpty || name == 'lo') continue;
    final values = line.substring(separator + 1).trim().split(RegExp(r'\s+'));
    if (values.length < 16) continue;
    final received = int.tryParse(values[0]);
    final transmitted = int.tryParse(values[8]);
    if (received == null ||
        transmitted == null ||
        received < 0 ||
        transmitted < 0) {
      continue;
    }
    result[name] = NetworkCounters(
      received: received,
      transmitted: transmitted,
    );
  }
  return result;
}

/// Per-interface deltas prevent spikes when adapters appear, disappear or reset.
class NetworkSpeedSampler {
  Map<String, NetworkCounters>? _previous;
  Duration? _timestamp;

  void reset() {
    _previous = null;
    _timestamp = null;
  }

  NetworkSpeed? sample(
    Map<String, NetworkCounters> counters,
    Duration timestamp,
  ) {
    final previous = _previous;
    final last = _timestamp;
    _previous = Map.of(counters);
    _timestamp = timestamp;
    if (previous == null || last == null) return null;
    final seconds =
        (timestamp - last).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return null;
    var received = 0;
    var transmitted = 0;
    for (final entry in counters.entries) {
      final old = previous[entry.key];
      if (old == null) continue;
      final rx = entry.value.received - old.received;
      final tx = entry.value.transmitted - old.transmitted;
      if (rx >= 0) received += rx;
      if (tx >= 0) transmitted += tx;
    }
    return NetworkSpeed(
      download: received / seconds,
      upload: transmitted / seconds,
    );
  }
}

String formatNetworkSpeed(double? bytesPerSecond) {
  if (bytesPerSecond == null ||
      !bytesPerSecond.isFinite ||
      bytesPerSecond < 0) {
    return '—';
  }
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
  var value = bytesPerSecond;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class NetworkHistoryPoint {
  const NetworkHistoryPoint(this.time, this.speed, this.online);
  final Duration time;
  final NetworkSpeed? speed;
  final bool? online;
}

class NetworkTelemetry {
  NetworkTelemetry({
    required this.speed,
    required Map<String, NetworkCounters> counters,
    required Iterable<NetworkHistoryPoint> history,
    this.error,
  }) : counters = Map.unmodifiable(counters),
       history = List.unmodifiable(history);
  final NetworkSpeed? speed;
  final Map<String, NetworkCounters> counters;
  final List<NetworkHistoryPoint> history;
  final String? error;
  int get received =>
      counters.values.fold(0, (total, item) => total + item.received);
  int get transmitted =>
      counters.values.fold(0, (total, item) => total + item.transmitted);
}

/// One bounded history for every taskbar and its popup. Failed reads insert a
/// gap, and the next successful read establishes a fresh rate baseline.
class NetworkTelemetryTracker {
  final _sampler = NetworkSpeedSampler();
  final _history = <NetworkHistoryPoint>[];
  NetworkTelemetry sample(
    Map<String, NetworkCounters> counters,
    Duration time,
    bool? online,
  ) {
    final speed = _sampler.sample(counters, time);
    return _record(counters, time, speed, online);
  }

  NetworkTelemetry failure(Duration time, bool? online, String error) {
    _sampler.reset();
    return _record({}, time, null, online, error: error);
  }

  NetworkTelemetry _record(
    Map<String, NetworkCounters> counters,
    Duration time,
    NetworkSpeed? speed,
    bool? online, {
    String? error,
  }) {
    _history.add(NetworkHistoryPoint(time, speed, online));
    if (_history.length > 60) _history.removeAt(0);
    return NetworkTelemetry(
      speed: speed,
      counters: counters,
      history: _history,
      error: error,
    );
  }
}

String formatNetworkBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
}
