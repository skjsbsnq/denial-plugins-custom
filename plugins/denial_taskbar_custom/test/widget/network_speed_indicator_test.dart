import 'package:denial_taskbar_custom/src/network_speed.dart';
import 'package:denial_taskbar_custom/src/network_speed_indicator.dart';
import 'package:denial_taskbar_custom/src/network_telemetry_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'full two-line rates fit with wide fonts and accessibility text',
    (tester) async {
      const samples = <NetworkSpeed?>[
        null,
        NetworkSpeed(download: 45600, upload: 35800),
        NetworkSpeed(download: 999999999, upload: 999999),
        NetworkSpeed(download: 999999999999999, upload: 999999999999),
      ];
      for (final scale in [1.0, 1.75, 2.5]) {
        double? stableWidth;
        for (final speed in samples) {
          var width = 0.0;
          await tester.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [
                networkTelemetryProvider.overrideWith(
                  (ref) => Stream.value(
                    NetworkTelemetry(speed: speed, counters: {}, history: []),
                  ),
                ),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  textTheme: const TextTheme(
                    labelSmall: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 160,
                        height: 44,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            width = networkSpeedIndicatorWidth(context);
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: width,
                                    child: TextButton(
                                      onPressed: () {},
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const NetworkSpeedIndicator(),
                                    ),
                                  ),
                                  const SizedBox(width: 40),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          stableWidth ??= width;
          expect(
            width,
            stableWidth,
            reason: 'Sampling must not move neighbors.',
          );
          for (final text in [
            '↑ ${formatNetworkSpeed(speed?.upload)}',
            '↓ ${formatNetworkSpeed(speed?.download)}',
          ]) {
            final finder = find.text(text);
            final widget = tester.widget<Text>(finder);
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            expect(widget.overflow, isNot(TextOverflow.ellipsis));
            expect(widget.softWrap, false);
            expect(widget.maxLines, 1);
            expect(widget.style?.fontSize, 12);
            expect(
              paragraph.getMaxIntrinsicWidth(double.infinity),
              lessThanOrEqualTo(paragraph.size.width + .01),
              reason:
                  'Full rate and unit must fit without scaling or clipping.',
            );
          }
          if (width + 40 > 160) {
            final scroll = tester.state<ScrollableState>(
              find.byType(Scrollable),
            );
            expect(scroll.position.maxScrollExtent, greaterThan(0));
          }
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
