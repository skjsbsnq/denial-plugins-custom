// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:desk_canvas/src/desktop_canvas.dart';
import 'package:desk_canvas/src/desktop_store.dart';
import 'package:desk_canvas/src/interaction_highlight.dart';
import 'package:desk_canvas/src/highlight_decoration.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _Windows extends Notifier<List<ApplicationWindow>> {
  @override
  List<ApplicationWindow> build() => const [];
  void activate([int id = 1]) => state = [
    ApplicationWindow(
      id: id,
      appId: 'fake',
      title: 'Fake',
      active: true,
      minimized: false,
    ),
  ];
}

final _windows = NotifierProvider<_Windows, List<ApplicationWindow>>(
  _Windows.new,
);

class _Services implements ShellServices {
  @override
  NotifierProvider<_Windows, List<ApplicationWindow>> windows(int monitorId) =>
      _windows;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Actions implements FileActions {
  int opens = 0;
  @override
  Future<void> open(DesktopItem item) async {
    opens++;
  }

  @override
  Future<void> trash(DesktopItem item) async {}
  @override
  Future<void> rename(String source, String target) async {}
}

class _Store extends DesktopStore {
  _Store(VoidCallback changed, _Actions actions)
    : super(
        onChanged: changed,
        actions: actions,
        environment: const {'HOME': '/unused'},
      );
  @override
  Future<void> start() async {
    items = const [
      DesktopItem(path: '/unused/Desktop/Fake', name: 'Fake', directory: false),
    ];
    loading = false;
    onChanged?.call();
  }

  @override
  Future<void> validateItem(DesktopItem item) async {}
  @override
  Future<void> save() async {}
}

void main() {
  testWidgets(
    'double-click, context dismissal and application focus release feedback',
    (tester) async {
      final actions = _Actions();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellSettingsProvider.overrideWith(_Settings.new)],
          child: ShellTheme(
            data: const ShellThemeData(),
            child: MaterialApp(
              home: DesktopCanvas(
                services: _Services(),
                monitorId: 1,
                bounds: const Rect.fromLTWH(0, 0, 800, 600),
                createStore: (changed) => _Store(changed, actions),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final icon = find.byType(DesktopHighlight);
      await tester.tap(icon);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<DesktopHighlight>(icon).selected, isTrue);
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(actions.opens, 1);
      expect(tester.widget<DesktopHighlight>(icon).selected, isFalse);

      final dynamic state = tester.state(find.byType(DesktopCanvas));
      final DesktopItem item = state.store.items.single as DesktopItem;
      state.choose(item);
      state.openMenuAt(const Offset(40, 40), item);
      await tester.pumpAndSettle();
      state.dismissPopup();
      await tester.pumpAndSettle();
      expect(tester.widget<DesktopHighlight>(icon).selected, isFalse);
      expect(tester.widget<DesktopHighlight>(icon).hoverEnabled, isTrue);
      // A new menu survives an old popup's deferred close callback.
      state.openMenuAt(const Offset(50, 50), item);
      await tester.pump();
      expect(state.menuPosition, isNotNull);
      state.dismissPopup();
      await tester.pumpAndSettle();
      state.choose(item);
      await tester.pump();
      final container = ProviderScope.containerOf(tester.element(icon));
      container.read(_windows.notifier).activate();
      await tester.pumpAndSettle();
      expect(tester.widget<DesktopHighlight>(icon).selected, isFalse);
      // A new desktop interaction wins over a queued focus cleanup.
      container.read(_windows.notifier).activate(2);
      state.choose(item);
      await tester.pumpAndSettle();
      expect(tester.widget<DesktopHighlight>(icon).selected, isTrue);

      // Other plugins own their closing popup lifetimes.
      final popups = container.read(shellPopupControllerProvider.notifier);
      final other = popups.show(
        debugLabel: 'Other plugin',
        builder: (_, _) => const SizedBox.shrink(),
      );
      other.close();
      state.openMenuAt(const Offset(50, 50), item);
      await tester.pumpAndSettle();
      expect(
        container
            .read(shellPopupControllerProvider)
            .any((p) => p.id == other.id && p.closing),
        isTrue,
      );
      final old = state.popup;
      popups.close(old.id as int);
      state.openMenuAt(const Offset(50, 50), item);
      await tester.pumpAndSettle();
      expect(state.menuPosition, isNotNull);
      expect(state.popup.id, isNot(old.id));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'synthetic enter with an old delta cannot restore cleared hover',
    (tester) async {
      final epoch = ValueNotifier(0);
      addTearDown(epoch.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellSettingsProvider.overrideWith(_Settings.new)],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: ValueListenableBuilder<int>(
                  valueListenable: epoch,
                  builder: (_, value, child) => DesktopHighlight(
                    feedbackEpoch: value,
                    theme: const ShellThemeData(),
                    child: child!,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final region = find
          .descendant(
            of: find.byType(DesktopHighlight),
            matching: find.byType(MouseRegion),
          )
          .first;
      tester.widget<MouseRegion>(region).onHover!(
        const PointerHoverEvent(delta: Offset(5, 0)),
      );
      await tester.pumpAndSettle();
      epoch.value++;
      await tester.pumpAndSettle();
      tester.widget<MouseRegion>(region).onEnter!(
        const PointerEnterEvent(delta: Offset(5, 0)),
      );
      await tester.pumpAndSettle();
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
      expect(decoration().color!.a, 0);
      tester.widget<MouseRegion>(region).onHover!(
        const PointerHoverEvent(delta: Offset(1, 0)),
      );
      await tester.pumpAndSettle();
      expect(decoration().color!.a, greaterThan(0));
    },
  );
}
