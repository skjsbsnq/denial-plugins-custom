import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_taskbar_custom/src/launch_icon_bounce.dart';
import 'package:denial_taskbar_custom/src/taskbar_icon_viewport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launches share an active hop and return to the exact baseline', (
    tester,
  ) async {
    var request = 0;
    var waiting = true;
    var enabled = true;
    late StateSetter update;
    const icon = SizedBox(key: ValueKey('icon'), width: 28, height: 28);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: SizedBox(
                  width: 48,
                  height: 44,
                  child: TaskbarIconViewport(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: LaunchIconBounce(
                        request: request,
                        waitingForWindow: waiting,
                        durationScale: 1,
                        panelTravel: 32,
                        enabled: enabled,
                        child: icon,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    double y() => tester.getTopLeft(find.byKey(const ValueKey('icon'))).dy;
    final baseline = y();
    await tester.pump(const Duration(milliseconds: 200));
    expect(y(), baseline, reason: 'Mounting must not trigger a launch.');
    update(() => request++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final moving = y();
    expect(moving, lessThan(baseline));
    expect(moving, greaterThanOrEqualTo(baseline - 18));
    update(() => request++);
    await tester.pump();
    expect(y(), moving, reason: 'Rapid launches must not reset position.');
    await tester.pump(const Duration(milliseconds: 120));
    expect(y(), closeTo(baseline - 18, .0001));
    final viewport = tester.getRect(find.byType(TaskbarIconViewport));
    expect(
      y(),
      lessThan(viewport.top),
      reason: 'The main hop must extend above the old bar viewport.',
    );
    final clip = tester.widget<ClipRect>(find.byType(ClipRect));
    final bounds = clip.clipper!.getClip(viewport.size);
    expect(bounds.top, -18);
    expect(bounds.left, 0);
    expect(
      bounds.right,
      viewport.width,
      reason: 'Horizontal scrolling boundaries must remain clipped.',
    );
    expect(bounds.bottom, viewport.height);
    // A slow application stays animated past the old fixed 720ms endpoint.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(y(), lessThan(baseline));
    final beforeWindow = y();
    update(() => waiting = false);
    await tester.pump();
    expect(y(), beforeWindow, reason: 'A window event must not snap the icon.');
    await tester.pumpAndSettle();
    expect(y(), baseline);
    await tester.pump(const Duration(seconds: 2));
    expect(y(), baseline, reason: 'No extra hops after the window appears.');
    update(() {
      request++;
      waiting = true;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(y(), lessThan(baseline));
    update(() => enabled = false);
    await tester.pump();
    expect(y(), baseline, reason: 'Dragging cancels the launch effect.');
    update(() {
      request++;
      enabled = true;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Dispose releases the ticker.',
    );
  });

  testWidgets(
    'reduced motion, hidden surfaces and disabled travel stay still',
    (tester) async {
      for (final mode in ['reduce', 'hidden', 'duration', 'travel']) {
        var request = 0;
        var disabled = false;
        late StateSetter update;
        await tester.pumpWidget(
          StatefulBuilder(
            key: UniqueKey(),
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQueryData(
                  disableAnimations: disabled && mode == 'reduce',
                ),
                child: ShellSurfacePresentation(
                  visible: !(disabled && mode == 'hidden'),
                  opacity: const AlwaysStoppedAnimation(1.0),
                  child: Center(
                    child: LaunchIconBounce(
                      request: request,
                      waitingForWindow: true,
                      durationScale: disabled && mode == 'duration' ? 0 : 1,
                      panelTravel: disabled && mode == 'travel' ? 0 : 32,
                      child: const SizedBox(width: 28, height: 28),
                    ),
                  ),
                ),
              );
            },
          ),
        );
        double translation() => tester
            .widget<Transform>(find.byType(Transform))
            .transform
            .storage[13];
        update(() => request++);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(translation(), lessThan(0));
        update(() => disabled = true);
        await tester.pump();
        expect(translation(), 0);
        update(() => request++);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(translation(), 0);
        update(() => disabled = false);
        await tester.pumpAndSettle();
        expect(
          translation(),
          0,
          reason: 'Hidden requests must not replay later.',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
