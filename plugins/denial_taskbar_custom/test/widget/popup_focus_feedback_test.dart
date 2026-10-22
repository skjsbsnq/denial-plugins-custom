import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_sdk/system.dart';
import 'package:denial_taskbar_custom/src/control_center.dart';
import 'package:denial_taskbar_custom/src/popup_focus_feedback.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _Battery extends BatteryController {
  @override
  BatteryStatus build() => BatteryStatus.unknown;
}

class _Services implements ShellServices {
  final _bounds = Provider<Rect?>((ref) => const Rect.fromLTWH(0, 0, 800, 600));
  @override
  Provider<Rect?> monitorBounds(int monitorId) => _bounds;
  @override
  final clock = Provider<AsyncValue<DateTime>>(
    (ref) => AsyncData(DateTime.now()),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget button) => ProviderScope(
  overrides: [
    shellSettingsProvider.overrideWith(_Settings.new),
    batteryProvider.overrideWith(_Battery.new),
  ],
  child: ShellServicesScope(
    services: _Services(),
    child: ShellTheme(
      data: const ShellThemeData(panelOpacity: 1),
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Scaffold(
          body: Align(alignment: Alignment.bottomRight, child: button),
        ),
      ),
    ),
  ),
);

Finder get _toggle => find
    .descendant(
      of: find.byType(ControlCenterButton),
      matching: find.byWidgetPredicate(
        (widget) => switch (widget) {
          IconButton(:final focusNode) || TextButton(:final focusNode) =>
            focusNode?.debugLabel == 'Control center toggle',
          _ => false,
        },
      ),
    )
    .first;

FocusNode _focus(WidgetTester tester) => switch (tester.widget(_toggle)) {
  IconButton(:final focusNode) => focusNode!,
  TextButton(:final focusNode) => focusNode!,
  _ => throw StateError('Expected a popup toggle.'),
};

Color? _overlay(WidgetTester tester, Set<WidgetState> states) => tester
    .widget<InkWell>(
      find.descendant(of: _toggle, matching: find.byType(InkWell)),
    )
    .overlayColor
    ?.resolve(states);

const _text = SizedBox(width: 100, height: 44, child: Text('date toggle'));

void main() {
  test(
    'pointer focus suppression preserves combined hover and press colors',
    () {
      final base = IconButton.styleFrom(overlayColor: Colors.black);
      final pointer = popupButtonFocusStyle(
        base,
        keyboard: false,
      ).overlayColor!;
      expect(pointer.resolve({WidgetState.focused}), Colors.transparent);
      for (final states in [
        {WidgetState.hovered},
        {WidgetState.pressed},
        {WidgetState.focused, WidgetState.hovered},
        {WidgetState.focused, WidgetState.pressed},
      ]) {
        expect(pointer.resolve(states), base.overlayColor!.resolve(states));
      }
      final keyboard = popupButtonFocusStyle(
        base,
        keyboard: true,
      ).overlayColor!;
      expect(
        keyboard.resolve({WidgetState.focused}),
        base.overlayColor!.resolve({WidgetState.focused}),
      );
    },
  );

  for (final entry in <String, Widget>{
    'controls': const ControlCenterButton(monitorId: 0),
    'battery': const ControlCenterButton.battery(monitorId: 0),
    'network': const ControlCenterButton.network(monitorId: 0, child: _text),
    'clock': const ControlCenterButton.clock(monitorId: 0, child: _text),
  }.entries) {
    testWidgets('${entry.key} separates pointer and keyboard focus feedback', (
      tester,
    ) async {
      await tester.pumpWidget(_host(entry.value));
      _focus(tester).requestFocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_overlay(tester, {WidgetState.focused})?.a, greaterThan(0));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_toggle));
      await mouse.down(tester.getCenter(_toggle));
      // Cancel instead of opening real device cards: this checks all four
      // buttons' feedback paths without reading or controlling system services.
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(_overlay(tester, {WidgetState.focused}), Colors.transparent);
      expect(_overlay(tester, {WidgetState.hovered})?.a, greaterThan(0));
      expect(_overlay(tester, {WidgetState.pressed})?.a, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_overlay(tester, {WidgetState.focused})?.a, greaterThan(0));
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      // Keyboard input after unmounting must remain safe.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'closing a clock card restores focus with the last input modality',
    (tester) async {
      await tester.pumpWidget(
        _host(const ControlCenterButton.clock(monitorId: 0, child: _text)),
      );
      final toggleFocus = _focus(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_toggle));
      Future<void> click(Finder target) async {
        final position = tester.getCenter(target);
        await mouse.moveTo(position);
        await mouse.down(position);
        await mouse.up();
        await tester.pumpAndSettle();
      }

      await click(_toggle);
      await click(find.byTooltip('Close'));
      await mouse.moveTo(const Offset(400, 580));
      await tester.pumpAndSettle();
      expect(toggleFocus.hasFocus, true);
      expect(_overlay(tester, {WidgetState.focused}), Colors.transparent);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(toggleFocus.hasFocus, true);
      expect(_overlay(tester, {WidgetState.focused})?.a, greaterThan(0));

      // The close action's input wins over how the panel was originally opened.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await click(find.byTooltip('Close'));
      expect(toggleFocus.hasFocus, true);
      expect(_overlay(tester, {WidgetState.focused}), Colors.transparent);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(tester.takeException(), isNull);
    },
  );
}
