import 'dart:io';

import 'package:denial_taskbar_custom/src/panel_motion.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final opening = PanelMotion(start: 0, initialVelocity: 0, target: 1);
  var previous = 0.0;
  for (var frame = 0; frame <= 144; frame++) {
    final position = opening.position(frame / 144);
    check(
      position >= previous - 1e-12 && position >= 0 && position <= 1,
      'An opening from rest must be monotonic without overshoot.',
    );
    previous = position;
  }
  check(
    opening.isDone(0.4),
    'Normal motion must not leave a long settling tail.',
  );

  for (final time in [0.015, 0.04, 0.08, 0.16, 0.25]) {
    final position = opening.position(time);
    final velocity = opening.velocity(time);
    final reverse = PanelMotion(
      start: position,
      initialVelocity: velocity,
      target: 0,
    );
    check(
      (reverse.position(0) - position).abs() < 1e-12,
      'Reversing must preserve the exact current position.',
    );
    check(
      (reverse.velocity(0) - velocity).abs() < 1e-12,
      'Reversing must preserve current velocity rather than restart the curve.',
    );
    final actualDerivative = (reverse.position(0.000001) - position) / 0.000001;
    check(
      (actualDerivative - velocity).abs() < 0.002,
      'The first frame after reversal must follow the incoming trajectory.',
    );
    check(reverse.isDone(0.6), 'Interrupted closing must eventually settle.');
  }

  var motion = opening;
  var target = 1.0;
  for (final delay in [0.03, 0.02, 0.06, 0.015, 0.08, 0.02]) {
    final position = motion.position(delay).clamp(0.0, 1.0);
    final velocity = motion.velocity(delay);
    target = 1 - target;
    motion = PanelMotion(
      start: position,
      initialVelocity: velocity,
      target: target,
    );
    check(
      (motion.position(0) - position).abs() < 1e-12 &&
          (motion.velocity(0) - velocity).abs() < 1e-12,
      'Rapid repeated taps must not reset the panel to an endpoint.',
    );
  }
  check(motion.isDone(0.7), 'Rapid taps must not leave an endless animation.');
  final slower = PanelMotion(
    start: 0,
    initialVelocity: 0,
    target: 1,
    durationScale: 2,
  );
  check(
    (slower.position(0.2) - opening.position(0.1)).abs() < 1e-12,
    'Denial animation speed must scale the same motion consistently.',
  );
  stdout.writeln(
    'Panel motion reversal, repeated-tap and settling regression checks passed.',
  );
}
