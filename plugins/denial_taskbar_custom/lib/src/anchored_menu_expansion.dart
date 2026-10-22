import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'control_center_layout.dart';

/// Matches the reference dashboard's notification-card expansion. Only the
/// material and reveal clip change size; foreground text is never scaled.
class AnchoredMenuExpansion extends StatelessWidget {
  const AnchoredMenuExpansion({
    required this.animation,
    required this.open,
    required this.origin,
    required this.target,
    required this.transitionFocus,
    required this.onBack,
    required this.controls,
    required this.detail,
    required this.detailFocus,
    super.key,
  });

  final Animation<double> animation;
  final bool open;
  final Rect origin;
  final Rect target;
  final FocusNode transitionFocus;
  final VoidCallback onBack;
  final Widget controls;
  final Widget detail;
  final FocusNode detailFocus;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    // Reuse the fixed foreground subtree while only the material, clip and
    // opacity move. Opacity already retains its own composited paint layer.
    final detailContent = Focus(
      focusNode: detailFocus,
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(12),
        child: detail,
      ),
    );
    return Focus(
      focusNode: transitionFocus,
      onKeyEvent: (_, event) {
        if ((open || animation.value > 0) &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (event is KeyDownEvent) onBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: animation,
        child: controls,
        builder: (context, child) {
          final t = animation.value;
          final transitioning = open || animation.value > 0;
          final ready = open && animation.value == 1;
          // Keep the endpoints measured at the tap. In-flight pixel
          // rounding made slow parts of the expansion visibly step.
          final interpolated = Rect.lerp(origin, target, t)!;
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final rect = t == 0 || t == 1
              ? Rect.fromLTRB(
                  snapToPhysicalPixel(interpolated.left, ratio),
                  snapToPhysicalPixel(interpolated.top, ratio),
                  snapToPhysicalPixel(interpolated.right, ratio),
                  snapToPhysicalPixel(interpolated.bottom, ratio),
                )
              : interpolated;
          final radius = 12 + (theme.panelRadius - 12) * t;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                ignoring: transitioning,
                child: ExcludeFocus(
                  excluding: transitioning,
                  child: ExcludeSemantics(
                    excluding: transitioning,
                    child: Opacity(opacity: 1 - t, child: child),
                  ),
                ),
              ),
              if (transitioning)
                Positioned.fill(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fromRect(
                        rect: rect,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                theme.accentPalette.container,
                                context.shellColors.surfaceContainer,
                                t,
                              ),
                              borderRadius: BorderRadius.circular(radius),
                              border: Border.all(
                                color: context.shellColors.hairlineSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: target,
                        child: IgnorePointer(
                          ignoring: !ready,
                          child: ExcludeFocus(
                            excluding: !ready,
                            child: ExcludeSemantics(
                              excluding: !ready,
                              child: ClipRRect(
                                clipper: _RevealClipper(
                                  rect.shift(-target.topLeft),
                                  radius,
                                ),
                                child: Opacity(
                                  opacity: const Interval(
                                    .45,
                                    .85,
                                  ).transform(animation.value),
                                  child: detailContent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<RRect> {
  const _RevealClipper(this.rect, this.radius);
  final Rect rect;
  final double radius;
  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));
  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      rect != oldClipper.rect || radius != oldClipper.radius;
}
