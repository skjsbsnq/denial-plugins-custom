import 'dart:io';

import 'package:denial_taskbar_custom/src/launch_bounce_motion.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  for (final fps in [60, 120, 144]) {
    final frames = (fps * .6).ceil();
    for (var frame = 0; frame <= frames; frame++) {
      final height = launchBounceHeight(frame / frames);
      check(height >= 0 && height <= 1, 'Motion must stay within its travel.');
    }
  }
  for (final endpoint in [0.0, 1.0]) {
    check(
      launchBounceHeight(endpoint) == 0,
      'Landings must be exactly aligned.',
    );
    const epsilon = .00001;
    final before = launchBounceHeight(endpoint - epsilon);
    final after = launchBounceHeight(endpoint + epsilon);
    check(
      (after - before).abs() / (2 * epsilon) < .00001,
      'No velocity discontinuity at takeoff or landing.',
    );
    check(
      (after + before).abs() / (epsilon * epsilon) < .02,
      'Landings must ease their acceleration to zero.',
    );
  }
  check(
    (launchBounceHeight(.5) - 1).abs() < 1e-12,
    'Every waiting hop reaches the intended height.',
  );
  for (final invalid in [-1.0, 2.0, double.nan, double.infinity]) {
    check(launchBounceHeight(invalid) == 0, 'Invalid progress must rest.');
  }
  check(
    launchBounceDuration(2) == const Duration(milliseconds: 1200),
    'Follow the Denial duration multiplier.',
  );
  for (final disabled in [0.0, -1.0, double.nan, double.infinity]) {
    check(
      launchBounceDuration(disabled) == Duration.zero,
      'Disabled or invalid durations must not create a ticker.',
    );
    check(
      launchBounceTravel(disabled) == 0,
      'Disabled or invalid travel must remain stationary.',
    );
  }
  check(
    launchBounceTravel(32) == 18 && launchBounceTravel(96) == 18,
    'Large travel settings must stay within the foreground overflow allowance.',
  );
  check(
    launchBounceTravel(16) == 9,
    'Small travel settings reduce hop height.',
  );
  stdout.writeln(
    'Launch bounce continuity, bounds and settings checks passed.',
  );
}
