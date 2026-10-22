import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'power_supply_readings.dart';

import 'package:denial_flutter_sdk/state.dart';

// Read only while a card observes it, shared across outputs. No extra poller.
// Opening, explicit Refresh and shared battery-state changes request a snapshot.
final powerSupplyReadingsProvider =
    FutureProvider.autoDispose<List<SupplyReading>>((ref) {
      ref.watch(batteryProvider);
      return readPowerSupplyReadings();
    });
