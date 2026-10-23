// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'highlight_decoration.dart';

/// Owns pointer feedback locally. Only the background animates; the foreground
/// neither moves nor rebuilds on hover. Borders never contribute layout padding.
class LauncherHighlight extends ConsumerStatefulWidget {
  const LauncherHighlight({
    super.key,
    required this.theme,
    required this.child,
    this.selected = false,
    this.idleColor = Colors.transparent,
    this.feedbackEpoch = 0,
    this.hoverEnabled = true,
  });
  final ShellThemeData theme;
  final Widget child;
  final bool selected;
  final Color idleColor;

  /// Changes whenever the launcher is hidden, reshown or rebuilt, so stale
  /// hover feedback cannot survive a layout change.
  final int feedbackEpoch;
  final bool hoverEnabled;
  @override
  ConsumerState<LauncherHighlight> createState() => _LauncherHighlightState();
}

class _LauncherHighlightState extends ConsumerState<LauncherHighlight> {
  bool hovered = false;

  /// MouseTracker can synthesize an enter with the last event's nonzero delta
  /// after the list scrolls beneath a still pointer. Only real motion resumes
  /// feedback, so scrolling does not light up every row that passes the cursor.
  bool _requiresMotion = false;

  @override
  void initState() {
    super.initState();
    if (!widget.hoverEnabled) _reset();
  }

  @override
  void didUpdateWidget(covariant LauncherHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.feedbackEpoch != oldWidget.feedbackEpoch ||
        widget.hoverEnabled != oldWidget.hoverEnabled ||
        !widget.hoverEnabled) {
      _reset();
    }
  }

  void _reset() {
    hovered = false;
    _requiresMotion = true;
  }

  void pointer({required bool inside, bool moved = false}) {
    if (inside && !widget.hoverEnabled) return;
    final before = hovered;
    if (!inside) {
      hovered = false;
    } else if (moved || !_requiresMotion) {
      hovered = true;
      _requiresMotion = false;
    }
    if (hovered != before) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(
      shellSettingsProvider.select((s) => s.animations.durationScale),
    );
    final theme = widget.theme;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
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
                : hovered
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
