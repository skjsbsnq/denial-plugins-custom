// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

/// Keeps the same BoxDecoration interpolation as AnimatedContainer, but ticks
/// invalidate only paint. Neither widgets nor layout run for animation frames.
class HighlightDecoration extends ImplicitlyAnimatedWidget {
  const HighlightDecoration({
    super.key,
    required super.duration,
    required super.curve,
    required this.decoration,
    required this.child,
  });
  final BoxDecoration decoration;
  final Widget child;
  @override
  ImplicitlyAnimatedWidgetState<HighlightDecoration> createState() =>
      _HighlightDecorationState();
}

class _HighlightDecorationState
    extends ImplicitlyAnimatedWidgetState<HighlightDecoration> {
  DecorationTween? _decoration;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _decoration = visitor(
      _decoration,
      widget.decoration,
      (dynamic value) => DecorationTween(begin: value as Decoration),
    ) as DecorationTween?;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: HighlightPainter(
      _decoration!.animate(animation),
      Directionality.of(context),
    ),
    child: widget.child,
  );
}

class HighlightPainter extends CustomPainter {
  HighlightPainter(this.decoration, this.textDirection)
    : super(repaint: decoration);
  final Animation<Decoration> decoration;
  final TextDirection textDirection;
  @override
  void paint(Canvas canvas, Size size) {
    final painter = decoration.value.createBoxPainter();
    try {
      painter.paint(
        canvas,
        Offset.zero,
        ImageConfiguration(size: size, textDirection: textDirection),
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(HighlightPainter oldDelegate) =>
      oldDelegate.decoration != decoration ||
      oldDelegate.textDirection != textDirection;
  @override
  bool shouldRebuildSemantics(HighlightPainter oldDelegate) => false;
}
