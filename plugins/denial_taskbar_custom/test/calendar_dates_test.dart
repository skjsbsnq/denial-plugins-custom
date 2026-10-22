import 'dart:io';

import 'package:denial_taskbar_custom/src/calendar_dates.dart';
import 'package:denial_taskbar_custom/src/battery_presentation.dart';
import 'package:denial_taskbar_custom/src/control_center_layout.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final leap = calendarDates(DateTime(2024, 2), firstWeekday: 0);
  check(
    leap.length == 42 && leap.first.weekday == DateTime.sunday,
    'Calendar must contain six complete Sunday-first weeks',
  );
  check(
    leap.where((day) => day.month == 2).length == 29,
    'Leap day must appear exactly once',
  );
  final january = calendarDates(DateTime(2026, 1), firstWeekday: 1);
  check(
    january.first.year == 2025 && january.first.weekday == DateTime.monday,
    'Leading year boundary and locale week start',
  );
  for (var i = 1; i < january.length; i++) {
    final previous = january[i - 1];
    check(
      sameCalendarDay(
        january[i],
        DateTime(previous.year, previous.month, previous.day + 1),
      ),
      'Calendar dates must be consecutive',
    );
  }
  check(
    utcOffsetLabel(const Duration(hours: 5, minutes: 30)) == 'GMT+5:30',
    'Half-hour time zone',
  );
  check(
    utcOffsetLabel(const Duration(hours: -3, minutes: -30)) == 'GMT-3:30',
    'Negative half-hour time zone',
  );
  check(
    estimatedBatteryCurrent(12, 12) == 1000,
    'Derived current must convert amperes to milliamperes',
  );
  for (final voltage in [null, 0.0, -1.0, double.nan, double.infinity]) {
    check(
      estimatedBatteryCurrent(12, voltage) == null,
      'Invalid voltages must remain unknown',
    );
  }
  check(
    estimatedBatteryCurrent(null, 12) == null,
    'Missing power must remain unknown',
  );
  final compact = controlCenterLayout(
    outputLeft: 0,
    outputTop: 0,
    outputRight: 1920,
    outputBottom: 1080,
    panelWidth: statsPanelWidth,
  )!;
  check(
    compact.width == 360 && compact.bottom == 1020,
    'Compact cards retain taskbar clearance',
  );
  final narrow = controlCenterLayout(
    outputLeft: 100,
    outputTop: 0,
    outputRight: 300,
    outputBottom: 500,
    panelWidth: statsPanelWidth,
  )!;
  check(
    narrow.width == 184 && narrow.right == 292,
    'Compact cards must fit narrow output boundaries',
  );
  stdout.writeln(
    'Calendar boundaries, leap years, time zones, unavailable telemetry and compact popup checks passed.',
  );
}
