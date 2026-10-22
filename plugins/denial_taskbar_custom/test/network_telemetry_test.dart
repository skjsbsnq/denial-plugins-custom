import 'dart:io';

import 'package:denial_taskbar_custom/src/network_speed.dart';
import 'package:denial_taskbar_custom/src/network_interface_details.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final tracker = NetworkTelemetryTracker();
  Map<String, NetworkCounters> counters(int n) => {
    'eth0': NetworkCounters(received: n * 1000, transmitted: n * 2000),
  };
  final first = tracker.sample(counters(10), Duration.zero, null);
  check(
    first.speed == null && first.history.single.online == null,
    'First sample and unknown connectivity remain unknown',
  );
  final second = tracker.sample(counters(11), const Duration(seconds: 2), true);
  check(
    second.speed!.download == 500 && second.speed!.upload == 1000,
    'Popup rates must use actual elapsed time',
  );
  check(
    second.received == 11000 && second.transmitted == 22000,
    'Totals must retain interface counter meaning',
  );
  final error = tracker.failure(
    const Duration(seconds: 3),
    false,
    'Test read failure',
  );
  check(
    error.speed == null &&
        error.counters.isEmpty &&
        error.history.last.speed == null &&
        error.error != null,
    'Failure produces a chart gap and clears stale totals',
  );
  final recovered = tracker.sample(
    counters(20),
    const Duration(seconds: 4),
    true,
  );
  check(
    recovered.speed == null && recovered.error == null,
    'Recovery must establish a new baseline',
  );
  for (var i = 21; i < 100; i++) {
    tracker.sample(counters(i), Duration(seconds: i), true);
  }
  final last = tracker.sample(
    counters(100),
    const Duration(seconds: 100),
    true,
  );
  check(
    last.history.length == 60 &&
        first.history.length == 1 &&
        second.history.length == 2,
    'History is bounded and earlier snapshots cannot mutate',
  );
  final switched = tracker.sample(
    {
      'wifi': const NetworkCounters(
        received: 999999999,
        transmitted: 999999999,
      ),
    },
    const Duration(seconds: 101),
    true,
  );
  check(
    switched.speed!.download == 0 && switched.speed!.upload == 0,
    'Interface changes cannot fabricate traffic spikes',
  );
  check(
    formatNetworkBytes(null) == '—' &&
        formatNetworkBytes(-1) == '—' &&
        formatNetworkBytes(0) == '0 B' &&
        formatNetworkBytes(1500) == '1.50 KB',
    'Total counters use decimal byte units',
  );

  final root = await Directory.systemTemp.createTemp('denial-network-test-');
  try {
    final eth = await Directory('${root.path}/eth0').create();
    await File('${eth.path}/operstate').writeAsString('up\n');
    await File('${eth.path}/address').writeAsString('02:11:22:33:44:55\n');
    await File('${eth.path}/speed').writeAsString('1000\n');
    final details = await readNetworkInterfaceDetails(
      ['../bad', 'eth0', 'removed'],
      root: root.path,
      localAddresses: {
        'eth0': ['192.0.2.2', '2001:db8::1', 'malformed'],
      },
    );
    check(
      details.length == 2 &&
          details.first.name == 'eth0' &&
          details.first.megabits == 1000,
      'Read valid interface details; skip traversal paths',
    );
    check(
      details.first.addresses.length == 2 && details.first.state == 'up',
      'Validate both IPv4 and IPv6 addresses',
    );
    check(
      details.last.mac == null && details.last.megabits == null,
      'Disappearing interfaces retain unknown fields',
    );
    await File('${eth.path}/speed').writeAsString('-1');
    await File('${eth.path}/address').writeAsString('a' * 200);
    final missing = (await readNetworkInterfaceDetails(
      ['eth0'],
      root: root.path,
      localAddresses: {},
    )).single;
    check(
      missing.mac == null && missing.megabits == null,
      'Unknown speed and oversized MAC must not become readings',
    );
  } finally {
    await root.delete(recursive: true);
  }
  stdout.writeln(
    'Network history limits, failure gaps, recovery, device changes and interface metadata checks passed.',
  );
}
