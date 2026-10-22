import 'dart:convert';
import 'dart:io';

/// Supplementary, read-only sysfs telemetry. Never substitutes rating/limit
/// attributes for measurements or treats battery voltage as adapter voltage.
class SupplyReading {
  const SupplyReading({
    required this.name,
    required this.battery,
    required this.charging,
    required this.watts,
    required this.amps,
    required this.volts,
    required this.estimatedWatts,
    required this.estimatedAmps,
  });
  final String name;
  final bool battery;
  final bool charging;
  final double? watts;
  final double? amps;
  final double? volts;
  final bool estimatedWatts;
  final bool estimatedAmps;
  bool get hasMeasurements => watts != null || amps != null || volts != null;
}

SupplyReading parseSupplyReading(String name, Map<String, String?> fields) {
  double? micro(String key, {bool positive = false}) {
    final raw = fields[key]?.trim() ?? '';
    if (!RegExp(r'^[+-]?\d{1,16}$').hasMatch(raw)) return null;
    final value = int.tryParse(raw)?.abs();
    if (value == null || value > 1000000000000 || (positive && value == 0)) {
      return null;
    }
    return value / 1000000;
  }

  final volts = micro('voltage_now', positive: true);
  final directAmps = micro('current_now');
  final directWatts = micro('power_now');
  return SupplyReading(
    name: name,
    battery: fields['type'] == 'Battery',
    charging: fields['status'] == 'Charging',
    volts: volts,
    watts:
        directWatts ??
        (directAmps != null && volts != null ? directAmps * volts : null),
    amps:
        directAmps ??
        (directWatts != null && volts != null ? directWatts / volts : null),
    estimatedWatts: directWatts == null && directAmps != null && volts != null,
    estimatedAmps: directAmps == null && directWatts != null && volts != null,
  );
}

Future<String?> _attribute(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    // sysfs reports synthetic lengths; bound the read itself, not stat().size.
    final bytes = await file.read(129);
    if (bytes.length > 128) return null;
    return utf8.decode(bytes).trim();
  } on FileSystemException catch (error) {
    // Missing/disappearing devices and unsupported individual readings.
    if ([2, 6, 19, 22, 61, 95].contains(error.osError?.errorCode)) return null;
    rethrow;
  } on FormatException {
    return null;
  } finally {
    await file?.close();
  }
}

Future<List<SupplyReading>> readPowerSupplyReadings({
  String root = '/sys/class/power_supply',
}) async {
  final result = <SupplyReading>[];
  var count = 0;
  try {
    await for (final device in Directory(root).list(followLinks: false)) {
      if (++count > 32) break;
      final name = device.path.split('/').last;
      if (!RegExp(r'^[a-zA-Z0-9_.:+-]{1,128}$').hasMatch(name)) continue;
      final type = await _attribute('${device.path}/type');
      final scope = await _attribute('${device.path}/scope');
      if (scope == 'Device') continue;
      final battery = type == 'Battery';
      if (!battery &&
          type != 'Mains' &&
          !(type?.startsWith('USB') ?? false) &&
          type != 'Wireless') {
        continue;
      }
      if (battery) {
        if (await _attribute('${device.path}/present') == '0') continue;
      } else if (await _attribute('${device.path}/online') != '1') {
        continue;
      }
      final fields = <String, String?>{'type': type};
      for (final attribute in [
        'status',
        'voltage_now',
        'current_now',
        'power_now',
      ]) {
        fields[attribute] = await _attribute('${device.path}/$attribute');
      }
      result.add(parseSupplyReading(name, fields));
    }
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode != 2) rethrow;
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return List.unmodifiable(result);
}

/// Keep the source visible. An adapter without telemetry must not mask actual
/// battery-side readings, and multiple batteries must not share a voltage.
List<SupplyReading> displayedSupplyReadings(List<SupplyReading> readings) {
  final adapters = readings
      .where((s) => !s.battery && s.hasMeasurements)
      .toList();
  if (adapters.isNotEmpty) return adapters;
  return readings
      .where((s) => s.battery && s.charging && s.hasMeasurements)
      .toList();
}
