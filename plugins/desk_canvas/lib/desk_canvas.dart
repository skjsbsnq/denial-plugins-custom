// SPDX-License-Identifier: GPL-3.0-or-later
@Plugin()
library;

import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'src/desktop_canvas.dart';

/// Desktop-plane contribution, independently installable from the launcher.
@Provides(ShellSurface)
final class DeskCanvasPlugin implements ShellSurface {
  const DeskCanvasPlugin();

  @override
  String get id => 'desk_canvas.desktop';

  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.desktop;

  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) {
    if (environment.workArea.isEmpty || !environment.isMainOutput) return null;

    return ShellSurfacePlacement(
      bounds: environment.workArea,
      // A fullscreen window covers the whole work area, so the icon plane has
      // nothing to contribute until the desktop itself is requested.
      visible:
          !environment.locked &&
          !environment.wallpaperSelectorVisible &&
          !environment.overview &&
          (!environment.fullscreen || environment.desktopVisible),
    );
  }

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) =>
      // Surfaces are mounted without a repaint boundary, so an icon-level
      // repaint would otherwise invalidate the whole scene, wallpaper included.
      RepaintBoundary(
        child: DesktopCanvas(
          services: surface.services,
          bounds: surface.environment.workArea,
          monitorId: surface.environment.output.monitorId,
        ),
      );
}
