// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:ui' show PointerDeviceKind;

import 'package:desk_canvas/src/interaction_highlight.dart';
import 'package:desk_canvas/src/highlight_decoration.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

void main() {
  testWidgets(
    'hover stays local, reverses continuously, and selection never moves content',
    (tester) async {
      var foregroundBuilds = 0;
      final selected = ValueNotifier(false);
      addTearDown(selected.dispose);
      const marker = ValueKey('foreground');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellSettingsProvider.overrideWith(_Settings.new)],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: ValueListenableBuilder<bool>(
                  valueListenable: selected,
                  builder: (context, value, child) => DesktopHighlight(
                    theme: const ShellThemeData(),
                    selected: value,
                    child: child!,
                  ),
                  child: Builder(
                    builder: (_) {
                      foregroundBuilds++;
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(key: marker),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byKey(marker));
      final builds = foregroundBuilds;
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(find.byType(DesktopHighlight)));
      await tester.pump();
      final painterBeforeTick = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(HighlightDecoration),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter;
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byType(HighlightDecoration),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter,
        same(painterBeforeTick),
      );
      BoxDecoration decoration() =>
          (tester
                          .widget<CustomPaint>(
                            find
                                .descendant(
                                  of: find.byType(HighlightDecoration),
                                  matching: find.byType(CustomPaint),
                                )
                                .first,
                          )
                          .painter!
                      as HighlightPainter)
                  .decoration
                  .value
              as BoxDecoration;
      final during = decoration().color!.a;
      expect(during, greaterThan(0));
      final expected = BoxDecoration.lerp(
        BoxDecoration(
          color: Colors.transparent,
          borderRadius: const ShellThemeData().borderRadius(4),
          border: Border.all(color: Colors.transparent),
        ),
        BoxDecoration(
          color: const ShellThemeData().accentPalette.subtle,
          borderRadius: const ShellThemeData().borderRadius(4),
          border: Border.all(color: Colors.transparent),
        ),
        Motion.standard.transform(30 / Motion.pill.inMilliseconds),
      )!;
      expect(decoration(), expected);
      await pointer.moveTo(Offset.zero);
      await tester.pump();
      expect(decoration().color!.a, closeTo(during, 0.0001));
      await tester.pump(const Duration(milliseconds: 20));
      expect(decoration().color!.a, lessThan(during));
      selected.value = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(marker)), before);
      selected.value = false;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(marker)), before);
      expect(foregroundBuilds, builds);
      expect(decoration().color!.a, 0);
      await pointer.removePointer();
    },
  );
}
