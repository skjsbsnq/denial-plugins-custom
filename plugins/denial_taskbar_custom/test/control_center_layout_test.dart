import 'dart:io';

import 'package:denial_taskbar_custom/src/control_center_layout.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final desktop = controlCenterLayout(
    outputLeft: 0,
    outputTop: 0,
    outputRight: 1920,
    outputBottom: 1080,
  )!;
  expect(
    desktop.width == 420 && desktop.maxHeight == 740,
    'Desktop should use the dashboard width and maximum height.',
  );
  expect(
    desktop.right == 1912 && desktop.bottom == 1020,
    'Popup must align to the output right edge and sit 8px above the 52px bar.',
  );

  final secondary = controlCenterLayout(
    outputLeft: 1920,
    outputTop: 240,
    outputRight: 3200,
    outputBottom: 960,
  )!;
  expect(
    secondary.right == 3192 && secondary.right - secondary.width >= 1928,
    'A secondary monitor must anchor to its own right edge.',
  );
  expect(
    secondary.maxHeight == 652 && secondary.bottom == 900,
    'Available height must account for the monitor vertical offset.',
  );

  final narrow = controlCenterLayout(
    outputLeft: 0,
    outputTop: 0,
    outputRight: 280,
    outputBottom: 260,
  )!;
  expect(
    narrow.width == 264 && narrow.right == 272 && narrow.maxHeight == 192,
    'Small outputs should shrink the panel and provide scrollable height.',
  );

  final scaled = controlCenterLayout(
    outputLeft: 0,
    outputTop: 0,
    outputRight: 1280.25,
    outputBottom: 720.25,
    devicePixelRatio: 1.5,
  )!;
  for (final value in [
    scaled.width,
    scaled.right,
    scaled.bottom,
    scaled.maxHeight,
  ]) {
    expect(
      (value * 1.5 - (value * 1.5).round()).abs() < 0.000001,
      'Fractional display scaling should place the settled panel on physical pixels.',
    );
  }

  expect(
    controlCenterLayout(
          outputLeft: 0,
          outputTop: 0,
          outputRight: 12,
          outputBottom: 200,
        ) ==
        null,
    'Do not create invalid constraints without horizontal space.',
  );
  expect(
    controlCenterLayout(
          outputLeft: 0,
          outputTop: 100,
          outputRight: 800,
          outputBottom: 150,
        ) ==
        null,
    'Do not render a popup without space above the bar.',
  );
  for (final ratio in [1.0, 1.25, 1.5, 1.75, 2.0]) {
    for (final measuredHeight in [328.0, 328.1, 517.25, 601.333333]) {
      final aligned = ceilToPhysicalPixel(measuredHeight, ratio);
      expect(
        aligned + 1e-8 >= measuredHeight &&
            aligned - measuredHeight < 1 / ratio + 1e-8,
        'Aligning content height must add less than one pixel and never clip it.',
      );
      final bottom = snapToPhysicalPixel(900, ratio);
      final top = bottom - aligned;
      expect(
        (top * ratio - (top * ratio).round()).abs() < 1e-8,
        'Bottom-anchored text must start at an aligned top edge.',
      );
    }
    for (final offset in [0.0, 0.2, 17.3333, 155.6, 452.0]) {
      final snapped = snapToPhysicalPixel(offset, ratio);
      expect(
        (snapped * ratio - (snapped * ratio).round()).abs() < 1e-8,
        'Animation travel must land on physical pixels.',
      );
      expect(
        (snapped - offset).abs() <= 0.5 / ratio + 1e-8,
        'Pixel alignment must not displace the panel by more than half a pixel.',
      );
    }
  }
  expect(
    ceilToPhysicalPixel(328, 1.25) == 328,
    'Repeated layouts must not grow an already aligned panel.',
  );
  expect(
    snapToPhysicalPixel(4.4, double.nan) == 4,
    'Invalid display ratios must fall back to a 1x pixel grid.',
  );

  final normalMenu = menuViewportBounds(
    bodyHeight: 640,
    bodyTopInViewport: 70,
    viewportHeight: 700,
  )!;
  expect(
    normalMenu.top == 0 && normalMenu.bottom == 614,
    'A menu below the header must fit the available viewport.',
  );
  final scrolledMenu = menuViewportBounds(
    bodyHeight: 800,
    bodyTopInViewport: -100,
    viewportHeight: 600,
  )!;
  expect(
    scrolledMenu.top == 116 && scrolledMenu.bottom == 684,
    'Scrolled menus must keep body coordinates instead of jumping to zero.',
  );
  expect(
    scrolledMenu.top - 100 == 16 && scrolledMenu.bottom - 100 == 584,
    'Both edges of a scrolled detail must retain the viewport padding.',
  );
  expect(
    menuViewportBounds(
          bodyHeight: 300,
          bodyTopInViewport: 700,
          viewportHeight: 600,
        ) ==
        null,
    'Offscreen controls must not generate inverted expansion bounds.',
  );

  stdout.writeln(
    'Control center screen-edge, bar clearance and fractional-scale checks passed.',
  );
}
