import 'dart:io';

import 'package:denial_taskbar_custom/src/power_supply_readings.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final battery = parseSupplyReading('BAT0', {
    'type': 'Battery',
    'status': 'Charging',
    'voltage_now': '15400000',
    'power_now': '4860000',
  });
  check(
    battery.volts == 15.4 && battery.watts == 4.86,
    'Micro-units must convert to volts and watts',
  );
  check(
    (battery.amps! - 4.86 / 15.4).abs() < 1e-9 && battery.estimatedAmps,
    'Missing measured current must be explicitly estimated',
  );
  final usb = parseSupplyReading('USB0', {
    'type': 'USB',
    'voltage_now': '20000000',
    'current_now': '2000000',
  });
  check(
    usb.amps == 2 &&
        !usb.estimatedAmps &&
        usb.watts == 40 &&
        usb.estimatedWatts,
    'Measured current and derived power',
  );
  final zero = parseSupplyReading('USB0', {
    'type': 'USB',
    'voltage_now': '0',
    'power_now': '0',
  });
  check(
    zero.volts == null && zero.watts == 0 && zero.amps == null,
    'Zero voltage cannot produce current; measured zero power is valid',
  );
  final invalid = parseSupplyReading('ADP', {
    'type': 'Mains',
    'voltage_now': 'NaN',
    'current_now': '9e9',
    'power_now': '12345678901234567890123456789',
    'voltage_max': '20000000',
    'current_max': '3000000',
  });
  check(
    !invalid.hasMeasurements,
    'Malformed and rated attributes must never become actual readings',
  );
  final direct = parseSupplyReading('ADP', {
    'type': 'Mains',
    'voltage_now': '20000000',
    'current_now': '1500000',
    'power_now': '25000000',
  });
  check(
    direct.watts == 25 &&
        direct.amps == 1.5 &&
        !direct.estimatedWatts &&
        !direct.estimatedAmps,
    'Measurements take priority over estimates',
  );
  check(
    displayedSupplyReadings([invalid, battery]).single == battery,
    'Adapter with no telemetry must fall back to labeled battery charging side',
  );
  check(
    displayedSupplyReadings([battery, direct]).single == direct,
    'Actual adapter readings take priority',
  );
  final discharging = parseSupplyReading('BAT1', {
    'type': 'Battery',
    'status': 'Discharging',
    'voltage_now': '12000000',
    'current_now': '-1000000',
  });
  check(
    displayedSupplyReadings([invalid, discharging]).isEmpty,
    'Do not present discharging battery as adapter charging data',
  );
  final root = await Directory.systemTemp.createTemp('denial-power-test-');
  Future<void> device(String name, Map<String, String> fields) async {
    final directory = await Directory('${root.path}/$name').create();
    for (final field in fields.entries) {
      await File('${directory.path}/${field.key}').writeAsString(field.value);
    }
  }

  try {
    await device('ADP', {'type': 'Mains', 'online': '1'});
    await device('BAT0', {
      'type': 'Battery',
      'present': '1',
      'status': 'Charging',
      'voltage_now': '15400000',
      'power_now': '4860000',
    });
    await device('USB-offline', {
      'type': 'USB',
      'online': '0',
      'voltage_now': '20000000',
      'current_now': '1000000',
    });
    await device('mouse', {
      'type': 'Battery',
      'scope': 'Device',
      'status': 'Charging',
      'voltage_now': '3000000',
    });
    await device('missing-battery', {
      'type': 'Battery',
      'present': '0',
      'voltage_now': '12000000',
    });
    await device('oversized', {
      'type': 'Mains',
      'online': '1',
      'voltage_now': '1' * 200,
    });
    final readings = await readPowerSupplyReadings(root: root.path);
    check(
      readings.length == 3,
      'Ignore offline ports, absent batteries and peripheral batteries',
    );
    check(
      !readings.firstWhere((s) => s.name == 'oversized').hasMeasurements,
      'Attribute size limit must apply to bytes read',
    );
    check(
      displayedSupplyReadings(readings).single.name == 'BAT0',
      'Device fixture should select real charging-side readings',
    );
    check(
      await File('${root.path}/BAT0/voltage_now').readAsString() == '15400000',
      'Adapter must remain read-only',
    );
  } finally {
    await root.delete(recursive: true);
  }
  check(
    (await readPowerSupplyReadings(root: '${root.path}/missing')).isEmpty,
    'Missing power interface has a safe empty fallback',
  );
  stdout.writeln(
    'Power-supply units, direct/derived readings, source selection, device filtering and bounded reads passed.',
  );
}
