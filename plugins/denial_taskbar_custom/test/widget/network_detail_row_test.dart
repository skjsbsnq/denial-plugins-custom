import 'package:denial_taskbar_custom/src/network_detail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'long SSID and IPv6 remain intact at ordinary and narrow widths',
    (tester) async {
      const name = 'Ciallo～(∠・ω<)⌒☆';
      const address = '2001:db8:1234:5678:90ab:cdef:1234:5678';
      for (final width in [360.0, 160.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NetworkDetailRow('网络：', name),
                          NetworkDetailRow('IPv6:', address),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final value in [name, address]) {
            final text = tester.widget<Text>(find.text(value));
            expect(text.softWrap, false);
            expect(text.maxLines, 1);
          }
          expect(find.byType(SelectionArea), findsNWidgets(2));
          if (width == 160) {
            expect(find.byType(SingleChildScrollView), findsWidgets);
          }
        }
      }
    },
  );
}
