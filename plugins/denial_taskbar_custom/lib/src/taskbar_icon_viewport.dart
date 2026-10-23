import 'package:flutter/widgets.dart';

import 'launch_bounce_motion.dart';

/// Preserve horizontal scrolling boundaries while allowing icons to jump above
/// the bar. The scrollable inside must use Clip.none; hit bounds stay unchanged.
class TaskbarIconViewport extends StatelessWidget {
  const TaskbarIconViewport({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ClipRect(clipper: const _IconViewportClipper(), child: child);
}

class _IconViewportClipper extends CustomClipper<Rect> {
  const _IconViewportClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -launchBounceMaxTravel, size.width, size.height);

  @override
  bool shouldReclip(_IconViewportClipper oldClipper) => false;
}
