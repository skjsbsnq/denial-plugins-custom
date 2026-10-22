import 'dart:math' as math;

const customTaskbarHeight = 52.0;
const statsPanelWidth = 360.0;

double _pixelScale(double scale) => scale.isFinite && scale > 0 ? scale : 1.0;

double snapToPhysicalPixel(double value, double devicePixelRatio) {
  final scale = _pixelScale(devicePixelRatio);
  return (value * scale).roundToDouble() / scale;
}

double ceilToPhysicalPixel(double value, double devicePixelRatio) {
  final scale = _pixelScale(devicePixelRatio);
  // Ignore floating-point error at an already aligned edge.
  return (value * scale - 1e-9).ceilToDouble() / scale;
}

/// Anchors the popup to its monitor's right edge and the top of the taskbar.
/// Coordinates are independent of the button width, the clock and tray items.
({double width, double maxHeight, double right, double bottom})?
controlCenterLayout({
  required double outputLeft,
  required double outputTop,
  required double outputRight,
  required double outputBottom,
  double devicePixelRatio = 1,
  double panelWidth = 420,
}) {
  const margin = 8.0;
  double snap(double value) => snapToPhysicalPixel(value, devicePixelRatio);
  final width = snap(
    math.min(panelWidth, math.max(0.0, outputRight - outputLeft - 2 * margin)),
  );
  final bottom = snap(outputBottom - customTaskbarHeight - margin);
  final maxHeight = snap(
    math.min(740.0, math.max(0.0, bottom - outputTop - margin)),
  );
  if (width <= 0 || maxHeight <= 0) return null;
  return (
    width: width,
    maxHeight: maxHeight,
    right: snap(outputRight - margin),
    bottom: bottom,
  );
}

/// The expanded card occupies the visible part of the controls at its current
/// scroll offset. Opening a menu must not move the originating corner button.
({double top, double bottom})? menuViewportBounds({
  required double bodyHeight,
  required double bodyTopInViewport,
  required double viewportHeight,
  double padding = 16,
}) {
  final top = math.max(0.0, padding - bodyTopInViewport);
  final bottom = math.min(
    bodyHeight,
    viewportHeight - bodyTopInViewport - padding,
  );
  if (bottom <= top) return null;
  return (top: top, bottom: bottom);
}
