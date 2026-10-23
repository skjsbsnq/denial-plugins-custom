import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:flutter/widgets.dart';

import 'launch_bounce_motion.dart';

/// A launch request changes [request]. Requests during a hop share its motion
/// instead of snapping the icon back to its resting position. Keep hopping
/// until the matching window arrives, then finish the current hop at rest.
class LaunchIconBounce extends StatefulWidget {
  const LaunchIconBounce({
    required this.request,
    required this.waitingForWindow,
    required this.durationScale,
    required this.panelTravel,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final int request;
  final bool waitingForWindow;
  final double durationScale;
  final double panelTravel;
  final bool enabled;
  final Widget child;

  @override
  State<LaunchIconBounce> createState() => _LaunchIconBounceState();
}

class _LaunchIconBounceState extends State<LaunchIconBounce>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  bool _visible = true;
  bool _reduceMotion = false;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        widget.waitingForWindow &&
        _canAnimate) {
      _motion.forward(from: 0);
    }
  }

  bool get _canAnimate =>
      widget.enabled &&
      _visible &&
      !_reduceMotion &&
      launchBounceDuration(widget.durationScale) > Duration.zero &&
      launchBounceTravel(widget.panelTravel) > 0;

  void _configure() {
    _motion.duration = launchBounceDuration(widget.durationScale);
    if (!_canAnimate) _motion.value = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = ShellSurfacePresentation.visibleOf(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _configure();
  }

  @override
  void didUpdateWidget(covariant LaunchIconBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
    if (widget.request != oldWidget.request &&
        _canAnimate &&
        !_motion.isAnimating) {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) => Transform.translate(
      // Keep the hit target, ink, focus and running indicators stationary.
      transformHitTests: false,
      offset: Offset(
        0,
        -launchBounceTravel(widget.panelTravel) *
            launchBounceHeight(_motion.value),
      ),
      child: child,
    ),
  );
}
