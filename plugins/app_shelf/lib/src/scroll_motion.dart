// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

/// Critically damped motion, matching the control center's response model.
/// Retargeting starts at the current position and velocity, not a new ease curve.
class ScrollMotion {
  ScrollMotion({
    required this.start,
    required this.velocity,
    required this.target,
    required this.minimum,
    required this.maximum,
    double scale = 1,
  }) : frequency = 30 / (scale.isFinite && scale > 0 ? scale : 1);
  final double start, velocity, target, minimum, maximum, frequency;
  double _position(double seconds) {
    final displacement = start - target;
    return target +
        (displacement + (velocity + frequency * displacement) * seconds) *
            math.exp(-frequency * seconds);
  }

  double position(double seconds) => _position(seconds).clamp(minimum, maximum);
  double speed(double seconds) {
    final raw = _position(seconds);
    if (raw < minimum || raw > maximum) return 0;
    return (velocity -
            frequency * (velocity + frequency * (start - target)) * seconds) *
        math.exp(-frequency * seconds);
  }

  bool done(double seconds) =>
      (_position(seconds) - target).abs() < 0.1 && speed(seconds).abs() < 1;
}

/// Reversing the wheel drops the pending distance but keeps physical velocity.
double scrollTarget({
  required double pixels,
  required double pending,
  required double delta,
  required double previousDirection,
  required double minimum,
  required double maximum,
}) => ((delta.sign == previousDirection ? pending : pixels) + delta).clamp(
  minimum,
  maximum,
);
