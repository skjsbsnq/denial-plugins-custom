import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_taskbar_custom/src/anchored_menu_expansion.dart';
import 'package:denial_taskbar_custom/src/clock_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}

class _ClockServices implements ShellServices {
  @override
  final clock = Provider<AsyncValue<DateTime>>(
    (ref) => AsyncData(DateTime.now()),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child) => ProviderScope(
  overrides: [shellSettingsProvider.overrideWith(_Settings.new)],
  child: ShellTheme(
    data: const ShellThemeData(panelOpacity: 1),
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 360, child: child),
        ),
      ),
    ),
  ),
);

class _PaintCounter extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}

void main() {
  testWidgets('seconds update the clock without rebuilding the calendar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ShellServicesScope(
          services: _ClockServices(),
          child: ClockPanel(onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    final calendar = tester.widget<Table>(find.byType(Table));
    final clock = find.byWidgetPredicate(
      (widget) => widget is ValueListenableBuilder<DateTime>,
    );
    final time = tester
        .widget<ValueListenableBuilder<DateTime>>(clock)
        .valueListenable;
    var ticks = 0;
    void recordTick() => ticks++;
    time.addListener(recordTick);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Table>(find.byType(Table)), same(calendar));
    }
    expect(ticks, 3);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final nextMonth = tester.widget<Table>(find.byType(Table));
    expect(nextMonth, isNot(same(calendar)));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Table>(find.byType(Table)), same(nextMonth));
    time.removeListener(recordTick);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'menu motion retains foreground paint, scrolling and input isolation',
    (tester) async {
      final motion = AnimationController(vsync: tester, value: .6);
      final transitionFocus = FocusNode();
      final detailFocus = FocusNode();
      final controlsPaint = _PaintCounter();
      final detailPaint = _PaintCounter();
      var open = true;
      var presses = 0;
      late StateSetter update;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AnchoredMenuExpansion(
                animation: motion,
                open: open,
                origin: const Rect.fromLTWH(280, 350, 28, 28),
                target: const Rect.fromLTWH(0, 0, 360, 400),
                transitionFocus: transitionFocus,
                detailFocus: detailFocus,
                onBack: () => update(() => open = false),
                controls: CustomPaint(
                  painter: controlsPaint,
                  child: const SizedBox(height: 400),
                ),
                detail: Column(
                  children: [
                    TextButton(
                      onPressed: () => presses++,
                      child: const Text('detail action'),
                    ),
                    CustomPaint(
                      painter: detailPaint,
                      child: const SizedBox(width: 300, height: 800),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final controlsBefore = controlsPaint.paints;
      final detailBefore = detailPaint.paints;
      for (final value in [.65, .75, .9, .95]) {
        motion.value = value;
        await tester.pump();
        expect(
          tester.widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView),
          ),
          same(scroll),
        );
      }
      expect(controlsPaint.paints, controlsBefore);
      expect(detailPaint.paints, detailBefore);
      await tester.tap(find.text('detail action'), warnIfMissed: false);
      expect(presses, 0);
      motion.value = 1;
      await tester.pump();
      await tester.tap(find.text('detail action'));
      expect(presses, 1);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      final state = tester.state<ScrollableState>(find.byType(Scrollable));
      final offset = state.position.pixels;
      expect(offset, greaterThan(0));
      update(() => open = false);
      motion.value = .7;
      await tester.pump();
      update(() => open = true);
      motion.value = 1;
      await tester.pump();
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        same(state),
      );
      expect(state.position.pixels, offset);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      motion.dispose();
      transitionFocus.dispose();
      detailFocus.dispose();
    },
  );
}
