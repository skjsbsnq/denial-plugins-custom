import 'dart:math' as math;

/// Critically damped panel motion. A reversal keeps both position and velocity
/// instead of restarting a duration curve at the new target.
class PanelMotion {
  PanelMotion({
    required this.start,
    required this.initialVelocity,
    required this.target,
    double durationScale = 1,
  }) : frequency =
           30 /
           (durationScale.isFinite && durationScale > 0 ? durationScale : 1);
  final double start;
  final double initialVelocity;
  final double target;
  final double frequency;

  double position(double seconds) {
    final displacement = start - target;
    final coefficient = initialVelocity + frequency * displacement;
    return target +
        (displacement + coefficient * seconds) * math.exp(-frequency * seconds);
  }

  double velocity(double seconds) {
    final coefficient = initialVelocity + frequency * (start - target);
    return (initialVelocity - frequency * coefficient * seconds) *
        math.exp(-frequency * seconds);
  }

  bool isDone(double seconds) =>
      (position(seconds) - target).abs() < 0.00025 &&
      velocity(seconds).abs() < 0.01 * frequency / 30;
}
