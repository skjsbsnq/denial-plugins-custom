import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';

/// Reveal the panel above the taskbar without scaling or fading foregrounds.
class ControlCenterReveal extends StatelessWidget {
  const ControlCenterReveal({
    required this.progress,
    required this.travel,
    required this.child,
    super.key,
  });
  final Animation<double> progress;
  final double travel;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    child: child,
    builder: (context, content) {
      final value = progress.value;
      // Keep the subtree mounted across the endpoints so native reads, menu
      // state and focus survive reversals. At rest only the panel's own clip
      // paints, avoiding doubled edge coverage around text and shell materials.
      return ClipRRect(
        clipBehavior: value == 1 ? Clip.none : Clip.antiAlias,
        clipper: _PanelRevealClipper(value, context.shellTheme.panelRadius),
        child: Transform.translate(
          offset: Offset(0, travel * (1 - value)),
          child: content,
        ),
      );
    },
  );
}

class _PanelRevealClipper extends CustomClipper<RRect> {
  const _PanelRevealClipper(this.progress, this.radius);
  final double progress;
  final double radius;
  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(
    Rect.fromLTRB(0, size.height * (1 - progress), size.width, size.height),
    Radius.circular(radius),
  );
  @override
  bool shouldReclip(_PanelRevealClipper oldClipper) =>
      progress != oldClipper.progress || radius != oldClipper.radius;
}
