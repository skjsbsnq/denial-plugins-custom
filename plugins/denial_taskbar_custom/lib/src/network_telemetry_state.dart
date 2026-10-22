import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';

import 'network_speed.dart';
import 'network_interface_details.dart';

// One stream and timer per shell provider scope, shared across taskbar outputs.
final networkTelemetryProvider = StreamProvider.autoDispose<NetworkTelemetry>((
  ref,
) {
  final tracker = NetworkTelemetryTracker();
  bool? online;
  ref.listen(networkConnectivityProvider, (_, value) {
    online = value.initializing || !value.snapshot.serviceAvailable
        ? null
        : value.snapshot.status == NetworkConnectivityStatus.online;
  }, fireImmediately: true);
  final clock = Stopwatch()..start();
  var stopped = false;
  var reading = false;
  Timer? timer;
  final updates = StreamController<NetworkTelemetry>();

  Future<void> sample() async {
    if (stopped || reading) return;
    reading = true;
    try {
      final content = await File('/proc/net/dev').readAsString();
      if (stopped) return;
      final all = parseNetworkCounters(content);
      // Physical NIC counters already include the traffic of bridges/VPNs.
      // Prefer them to avoid counting the same packets on stacked interfaces.
      final physical = <String, NetworkCounters>{};
      for (final entry in all.entries) {
        if (await Directory('/sys/class/net/${entry.key}/device').exists()) {
          physical[entry.key] = entry.value;
        }
      }
      if (!stopped) {
        updates.add(
          tracker.sample(
            physical.isEmpty ? all : physical,
            clock.elapsed,
            online,
          ),
        );
      }
    } on FileSystemException catch (error) {
      if (!stopped) {
        updates.add(tracker.failure(clock.elapsed, online, error.message));
      }
    } finally {
      reading = false;
    }
  }

  updates.onListen = () {
    unawaited(sample());
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(sample()),
    );
  };
  ref.onDispose(() {
    stopped = true;
    timer?.cancel();
    clock.stop();
    unawaited(updates.close());
  });
  return updates.stream;
});

// Only a device-set change or SDK network event invalidates metadata. Ordinary
// per-second counter updates do not re-enumerate addresses or create a poller.
final networkInterfaceDetailsProvider = FutureProvider.autoDispose((ref) {
  final names = ref.watch(
    networkTelemetryProvider.select((value) {
      final names = value.value?.counters.keys.toList() ?? <String>[];
      names.sort();
      return names.join('\n');
    }),
  );
  ref.watch(networkConnectivityProvider.select((state) => state.snapshot));
  return readNetworkInterfaceDetails(names.isEmpty ? [] : names.split('\n'));
});
