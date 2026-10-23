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

  /// Keeping one evaluated animation means a rebuild of the surrounding row no
  /// longer looks like a changed painter, so the decoration is not repainted
  /// for a colour that did not move.
  late Animation<Decoration> _evaluated;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _decoration = visitor(
      _decoration,
      widget.decoration,
      (dynamic value) => DecorationTween(begin: value as Decoration),
    ) as DecorationTween?;
    _evaluated = _decoration!.animate(animation);
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: HighlightPainter(_evaluated, Directionality.of(context)),
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
      !identical(oldDelegate.decoration, decoration) ||
      oldDelegate.textDirection != textDirection ||
      !identical(oldDelegate.decoration.value, decoration.value);
  @override
  bool shouldRebuildSemantics(HighlightPainter oldDelegate) => false;
}
