// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:app_shelf/src/smooth_scroll.dart';
import 'package:app_shelf/src/entry_retention.dart';
import 'package:app_shelf/src/retained_launcher_entry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'wheel resolver uses continuous motion; touchpad and reduced motion stay native',
    (tester) async {
      var reduced = false;
      final scroll = LauncherScrollController(
        motionScale: () => 1,
        animationsDisabled: () => reduced,
      );
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Listener(
            onPointerSignal: scroll.observeSignal,
            child: ListView.builder(
              controller: scroll,
              itemExtent: 36,
              itemCount: 100,
              itemBuilder: (_, i) => Text('App $i'),
            ),
          ),
        ),
      );
      Future<void> wheel(
        double delta, [
        PointerDeviceKind kind = PointerDeviceKind.mouse,
      ]) => tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(200, 200),
          scrollDelta: Offset(0, delta),
          kind: kind,
        ),
      );
      await wheel(120);
      expect(scroll.offset, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(scroll.offset, greaterThan(0));
      expect(scroll.offset, lessThan(120));
      await wheel(120);
      expect(scroll.destination, 240);
      final before = scroll.offset;
      await wheel(-60);
      expect(scroll.offset, before);
      expect(
        scroll.destination,
        (before - 60).clamp(0, scroll.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(200);
      await wheel(60, PointerDeviceKind.trackpad);
      expect(scroll.offset, 260);
      reduced = true;
      await wheel(60);
      expect(scroll.offset, 320);
      reduced = false;
      scroll.reveal(1800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      scroll.reveal(0);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      // Disposing during a running activity cancels its ticker cleanly.
      await wheel(120);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'visited row loaders survive short scrolls and eviction stays bounded',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final pool = EntryRetention(24);
      final builds = <int, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 200,
            child: ListView.builder(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemExtent: 40,
              itemCount: 200,
              itemBuilder: (_, i) => RetainedLauncherEntry(
                key: ValueKey(i),
                id: '$i',
                retention: pool,
                child: _LoadProbe(
                  onMount: () =>
                      builds.update(i, (n) => n + 1, ifAbsent: () => 1),
                ),
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(builds[0], 1);
      scroll.jumpTo(4000);
      await tester.pumpAndSettle();
      expect(pool.length, lessThanOrEqualTo(24));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(pool.length, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _LoadProbe extends StatefulWidget {
  const _LoadProbe({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_LoadProbe> createState() => _LoadProbeState();
}

class _LoadProbeState extends State<_LoadProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('App');
}
