// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

import 'scroll_motion.dart';

/// Uses Flutter's existing pointer-signal resolver and scroll activities. Native
/// drag/pan-zoom gestures, scrollbars, accessibility and nested edges stay intact.
class LauncherScrollController extends ScrollController {
  LauncherScrollController({
    required this.motionScale,
    required this.animationsDisabled,
  });
  final double Function() motionScale;
  final bool Function() animationsDisabled;
  bool _mouseWheel = false;

  // An outer listener observes the signal before the resolver invokes the
  // Scrollable's registered pointerScroll callback after hit-test dispatch.
  void observeSignal(PointerSignalEvent event) {
    _mouseWheel =
        event is PointerScrollEvent && event.kind == PointerDeviceKind.mouse;
  }

  bool get animate => !animationsDisabled() && motionScale() > 0;
  double get destination =>
      hasClients ? (position as _LauncherScrollPosition).destination : 0;
  void reveal(double target) {
    if (!hasClients) return;
    (position as _LauncherScrollPosition).smoothTo(target);
  }

  void stop() {
    if (hasClients) jumpTo(offset);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _LauncherScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    owner: this,
  );
}

class _LauncherScrollPosition extends ScrollPositionWithSingleContext {
  _LauncherScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.owner,
  }) : super(
         initialPixels: owner.initialScrollOffset,
         keepScrollOffset: owner.keepScrollOffset,
       );
  final LauncherScrollController owner;
  double get destination => activity is _WheelActivity
      ? (activity! as _WheelActivity).target
      : pixels;

  @override
  void pointerScroll(double delta) {
    final animate =
        owner._mouseWheel &&
        owner.animate &&
        delta != 0 &&
        hasContentDimensions;
    owner._mouseWheel = false;
    if (!animate) {
      super.pointerScroll(delta);
      return;
    }
    final current = activity;
    final target = scrollTarget(
      pixels: pixels,
      pending: destination,
      delta: delta,
      previousDirection: current is _WheelActivity ? current.direction : 0,
      minimum: minScrollExtent,
      maximum: maxScrollExtent,
    );
    _drive(target, delta.sign);
  }

  void smoothTo(double value) {
    final target = value.clamp(minScrollExtent, maxScrollExtent);
    if (!owner.animate) {
      jumpTo(target);
    } else {
      _drive(target, 0);
    }
  }

  void reshape(double target, double direction) {
    if (!owner.animate) {
      jumpTo(target.clamp(minScrollExtent, maxScrollExtent));
    } else {
      _drive(
        target.clamp(minScrollExtent, maxScrollExtent),
        direction,
        restart: true,
      );
    }
  }

  void _drive(double target, double direction, {bool restart = false}) {
    final current = activity;
    if (!restart && current is _WheelActivity && current.target == target) {
      return;
    }
    if (target == pixels && current is! _WheelActivity) return;
    final velocity = current is _WheelActivity ? current.velocity : 0.0;
    updateUserScrollDirection(
      target < pixels ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    beginActivity(
      _WheelActivity(
        this,
        _ScrollSimulation(
          ScrollMotion(
            start: pixels,
            velocity: velocity,
            target: target,
            minimum: minScrollExtent,
            maximum: maxScrollExtent,
            scale: owner.motionScale(),
          ),
        ),
        context.vsync,
        target,
        direction,
      ),
    );
  }
}

class _WheelActivity extends BallisticScrollActivity {
  _WheelActivity(
    ScrollActivityDelegate delegate,
    Simulation simulation,
    TickerProvider vsync,
    this.target,
    this.direction,
  ) : super(delegate, simulation, vsync, false);
  final double target, direction;
  @override
  void applyNewDimensions() =>
      (delegate as _LauncherScrollPosition).reshape(target, direction);
  @override
  void resetActivity() =>
      (delegate as _LauncherScrollPosition).reshape(target, direction);
}

class _ScrollSimulation extends Simulation {
  _ScrollSimulation(this.motion);
  final ScrollMotion motion;
  @override
  double x(double time) =>
      motion.done(time) ? motion.target : motion.position(time);
  @override
  double dx(double time) => motion.done(time) ? 0 : motion.speed(time);
  @override
  bool isDone(double time) => motion.done(time);
}
