import 'dart:io';

import 'package:denial_taskbar_custom/src/window_activation.dart';

void main() {
  for (final active in [false, true]) {
    for (final minimized in [false, true]) {
      final result = shouldMinimizeWindow(active: active, minimized: minimized);
      if (result != (active && !minimized)) {
        throw StateError(
          'Unexpected activation for active=$active minimized=$minimized',
        );
      }
    }
  }
  stdout.writeln(
    'Focused, background and minimized window activation checks passed.',
  );
}
