// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'highlight_decoration.dart';
import 'hover_feedback.dart';

/// Owns pointer feedback locally. Only the background animates; the foreground
/// neither moves nor rebuilds on hover. Borders never contribute layout padding.
class DesktopHighlight extends ConsumerStatefulWidget {
  const DesktopHighlight({
    super.key,
    required this.theme,
    required this.child,
    this.selected = false,
    this.feedbackEpoch = 0,
    this.hoverEnabled = true,
    this.idleColor = Colors.transparent,
  });
  final ShellThemeData theme;
  final Widget child;
  final bool selected;
  final int feedbackEpoch;
  final bool hoverEnabled;
  final Color idleColor;
  @override
  ConsumerState<DesktopHighlight> createState() => _DesktopHighlightState();
}

class _DesktopHighlightState extends ConsumerState<DesktopHighlight> {
  final feedback = DesktopHoverFeedback();
  @override
  void initState() {
    super.initState();
    if (!widget.hoverEnabled) feedback.reset();
  }

  @override
  void didUpdateWidget(covariant DesktopHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.feedbackEpoch != oldWidget.feedbackEpoch ||
        widget.hoverEnabled != oldWidget.hoverEnabled ||
        !widget.hoverEnabled) {
      feedback.reset();
    }
  }

  void pointer({required bool inside, bool moved = false}) {
    if (inside && !widget.hoverEnabled) return;
    if (feedback.update(inside: inside, moved: moved)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(
      shellSettingsProvider.select((s) => s.animations.durationScale),
    );
    final theme = widget.theme;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      // MouseTracker can synthesize an enter with the last event's nonzero
      // delta after an overlay moves. Only an actual hover resumes feedback.
      onEnter: (_) => pointer(inside: true),
      onHover: (event) =>
          pointer(inside: true, moved: event.delta.distanceSquared > 0),
      onExit: (_) => pointer(inside: false),
      child: RepaintBoundary(
        child: HighlightDecoration(
          duration: disabled
              ? Duration.zero
              : Duration(
                  microseconds: (Motion.pill.inMicroseconds * scale).round(),
                ),
          curve: Motion.standard,
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.accentPalette.selection
                : feedback.hovered
                ? theme.accentPalette.subtle
                : widget.idleColor,
            borderRadius: theme.borderRadius(4),
            border: Border.all(
              color: widget.selected
                  ? theme.accentPalette.primary
                  : Colors.transparent,
            ),
          ),
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}
