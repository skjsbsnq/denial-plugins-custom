import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keep each entry's travel fixed, so rapid reversals do not jump old pages.
/// Only translation and clipping are used; glyphs keep their original size.
class PanelContentTransition extends ConsumerWidget {
  const PanelContentTransition({
    required this.identity,
    required this.direction,
    required this.child,
    super.key,
  });
  final Object identity;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shellSettingsProvider).animations;
    final duration = panelInteractionDuration(context, settings.durationScale);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _slideEntry,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            for (final entry in previous)
              Offstage(
                child: IgnorePointer(
                  child: ExcludeFocus(child: ExcludeSemantics(child: entry)),
                ),
              ),
            ?current,
          ],
        ),
        child: _ContentEntry(
          key: ValueKey(identity),
          travel: direction * settings.panelTravel.clamp(0.0, 18.0),
          // The calendar/title can retain their paint while translated.
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

Duration panelInteractionDuration(BuildContext context, double scale) =>
    MediaQuery.disableAnimationsOf(context) || !scale.isFinite || scale <= 0
    ? Duration.zero
    : Duration(microseconds: (220000 * scale).round());

Widget _slideEntry(Widget child, Animation<double> animation) {
  final entry = child as _ContentEntry;
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, content) => Transform.translate(
      offset: Offset(entry.travel * (1 - animation.value), 0),
      child: content,
    ),
  );
}

class _ContentEntry extends StatelessWidget {
  const _ContentEntry({required this.travel, required this.child, super.key});
  final double travel;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
