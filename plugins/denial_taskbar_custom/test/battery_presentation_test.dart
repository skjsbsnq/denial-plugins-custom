import 'dart:io';

import 'package:denial_taskbar_custom/src/battery_presentation.dart';

void main() {
  void check(bool value) {
    if (!value) throw StateError('Power mode presentation regression');
  }

  const initial = PowerModePresentation(
    available: false,
    refreshing: false,
    changing: false,
    profile: 'balanced',
  );
  check(!initial.canSelect && !initial.isSelected('balanced'));
  const reading = PowerModePresentation(
    available: true,
    refreshing: true,
    changing: false,
    profile: 'power-save',
  );
  check(!reading.canSelect && reading.isSelected('power-save'));
  const changing = PowerModePresentation(
    available: true,
    refreshing: false,
    changing: true,
    profile: 'balanced',
  );
  check(!changing.canSelect && !changing.isSelected('performance'));
  const ready = PowerModePresentation(
    available: true,
    refreshing: false,
    changing: false,
    profile: 'performance',
  );
  check(ready.canSelect && ready.isSelected('performance'));
  stdout.writeln(
    'Power mode initialization, refresh and switching presentation checks passed.',
  );
}
