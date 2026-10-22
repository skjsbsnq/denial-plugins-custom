import 'dart:io';

import 'package:denial_taskbar_custom/src/network_speed.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Map<String, NetworkCounters> counters(int rx, int tx) => {
  'eth0': NetworkCounters(received: rx, transmitted: tx),
};

void main() {
  final parsed = parseNetworkCounters('''
Inter-| Receive | Transmit
 lo: 999 0 0 0 0 0 0 0 888 0 0 0 0 0 0 0
 eth0: 1000 1 2 3 4 5 6 7 2000 9 10 11 12 13 14 15
 bad: 1 2
 negative: -1 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0
 invalid: nope 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0
''');
  check(
    parsed.length == 1 &&
        parsed['eth0']?.received == 1000 &&
        parsed['eth0']?.transmitted == 2000,
    'Parse byte columns and exclude malformed/loopback records.',
  );
  final sampler = NetworkSpeedSampler();
  check(
    sampler.sample(counters(1000, 2000), Duration.zero) == null,
    'First sample is a baseline.',
  );
  var speed = sampler.sample(counters(5000, 3000), const Duration(seconds: 2))!;
  check(
    speed.download == 2000 && speed.upload == 500,
    'Actual elapsed time and direction.',
  );
  speed = sampler.sample({
    ...counters(6000, 3500),
    'wifi': const NetworkCounters(received: 9000000, transmitted: 8000000),
  }, const Duration(seconds: 3))!;
  check(
    speed.download == 1000 && speed.upload == 500,
    'New adapters cannot cause spikes.',
  );
  speed = sampler.sample(counters(6500, 3750), const Duration(seconds: 4))!;
  check(
    speed.download == 500 && speed.upload == 250,
    'Removed adapters cannot subtract traffic.',
  );
  speed = sampler.sample(counters(0, 0), const Duration(seconds: 5))!;
  check(
    speed.download == 0 && speed.upload == 0,
    'Counter resets cannot produce negative rates.',
  );
  speed = sampler.sample(counters(500, 250), const Duration(seconds: 6))!;
  check(
    speed.download == 500 && speed.upload == 250,
    'Recover after counter reset.',
  );
  speed = sampler.sample(counters(500, 250), const Duration(seconds: 7))!;
  check(speed.download == 0 && speed.upload == 0, 'Idle traffic is zero.');
  check(
    sampler.sample(counters(500, 250), const Duration(seconds: 7)) == null,
    'No division by zero.',
  );
  sampler.reset();
  check(
    sampler.sample(counters(600, 300), const Duration(seconds: 8)) == null,
    'Failure requires fresh baseline.',
  );
  check(
    formatNetworkSpeed(null) == '—' &&
        formatNetworkSpeed(double.nan) == '—' &&
        formatNetworkSpeed(double.infinity) == '—' &&
        formatNetworkSpeed(-1) == '—',
    'Unknown rate placeholder.',
  );
  check(
    formatNetworkSpeed(0) == '0 B/s' &&
        formatNetworkSpeed(1500) == '1.5 KB/s' &&
        formatNetworkSpeed(1000000) == '1.0 MB/s',
    'Decimal byte-rate units.',
  );
  stdout.writeln(
    'Network parsing, rate sampling and formatting checks passed.',
  );
}
