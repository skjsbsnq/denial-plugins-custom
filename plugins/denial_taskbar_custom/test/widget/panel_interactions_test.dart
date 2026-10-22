import 'dart:async';

import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denial_taskbar_custom/src/panel_content_transition.dart';
import 'package:denial_taskbar_custom/src/power_mode_selector.dart';

class _Settings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _Modes extends DesktopPowerModesController {
  Completer<void>? pending;
  int requests = 0;
  bool fail = false;
  @override
  DesktopPowerModesState build() =>
      DesktopPowerModesState.initial().copyWith(systemAvailable: true);
  @override
  Future<void> selectSystemProfile(String profile) async {
    requests++;
    state = state.copyWith(systemChanging: true, clearError: true);
    pending = Completer<void>();
    await pending!.future;
    state = fail
        ? state.copyWith(systemChanging: false, error: 'Test rejection')
        : state.copyWith(systemChanging: false, systemProfile: profile);
  }
}

Widget _host(Widget child, {_Modes? modes, bool reduce = false}) =>
    ProviderScope(
      overrides: [
        shellSettingsProvider.overrideWith(_Settings.new),
        if (modes != null) desktopPowerModesProvider.overrideWith(() => modes),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 360, child: child),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'month entries slide, survive rapid reversal, and retire old input',
    (tester) async {
      var page = 1;
      var presses = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, update) => Column(
              children: [
                TextButton(
                  onPressed: () => update(() => page++),
                  child: const Text('next'),
                ),
                TextButton(
                  onPressed: () => update(() => page--),
                  child: const Text('previous'),
                ),
                PanelContentTransition(
                  identity: page,
                  direction: page == 1 ? -1 : 1,
                  child: TextButton(
                    onPressed: () => presses++,
                    child: Text('page $page'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('next'));
      await tester.pump();
      expect(find.text('page 1'), findsNothing);
      expect(find.text('page 2'), findsOneWidget);
      final start = tester.getTopLeft(find.text('page 2')).dx;
      await tester.pump(const Duration(milliseconds: 90));
      final middle = tester.getTopLeft(find.text('page 2')).dx;
      expect(middle, lessThan(start));
      await tester.tap(find.text('previous'));
      await tester.pump();
      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      expect(find.text('page 2'), findsOneWidget);
      expect(find.text('page 1'), findsNothing);
      await tester.tap(find.text('page 2'));
      expect(presses, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion settles immediately', (tester) async {
    var page = 1;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, update) => Column(
            children: [
              TextButton(
                onPressed: () => update(() => page++),
                child: const Text('next'),
              ),
              PanelContentTransition(
                identity: page,
                direction: 1,
                child: Text('page $page'),
              ),
            ],
          ),
        ),
        reduce: true,
      ),
    );
    final resting = tester.getTopLeft(find.text('page 1')).dx;
    await tester.tap(find.text('next'));
    await tester.pump();
    expect(tester.getTopLeft(find.text('page 2')).dx, resting);
    expect(find.text('page 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending mode waits for confirmation, blocks duplicate clicks and preserves failures',
    (tester) async {
      final modes = _Modes();
      await tester.pumpWidget(_host(const PowerModeSelector(), modes: modes));
      await tester.tap(find.text('Performance'));
      await tester.pump();
      expect(modes.state.systemProfile, PowerProfile.balanced);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Power saver'));
      expect(modes.requests, 1);
      modes.pending!.complete();
      await tester.pumpAndSettle();
      expect(modes.state.systemProfile, PowerProfile.performance);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      modes.fail = true;
      await tester.tap(find.text('Power saver'));
      await tester.pump();
      modes.pending!.complete();
      await tester.pumpAndSettle();
      expect(modes.state.systemProfile, PowerProfile.performance);
      expect(find.text('Test rejection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
