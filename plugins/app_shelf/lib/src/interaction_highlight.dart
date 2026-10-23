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
  });
  final ShellThemeData theme;
  final Widget child;
  final bool selected;
  final Color idleColor;
  @override
  ConsumerState<LauncherHighlight> createState() => _LauncherHighlightState();
}

class _LauncherHighlightState extends ConsumerState<LauncherHighlight> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(
      shellSettingsProvider.select((s) => s.animations.durationScale),
    );
    final theme = widget.theme;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
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
