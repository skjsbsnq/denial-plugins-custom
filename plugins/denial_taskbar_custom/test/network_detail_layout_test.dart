import 'dart:io';

import 'package:denial_taskbar_custom/src/network_detail_layout.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final name = networkDetailLayout(
    availableWidth: 328,
    labelWidth: 48,
    valueWidth: 240,
  );
  check(
    !name.stacked && !name.scrollValue,
    'Wi-Fi name that fits the full remaining width must not be squeezed into half a row',
  );
  final ipv6 = networkDetailLayout(
    availableWidth: 328,
    labelWidth: 48,
    valueWidth: 312,
  );
  check(
    ipv6.stacked && !ipv6.scrollValue,
    'IPv6 gets a full-width line before any scrolling is needed',
  );
  final narrow = networkDetailLayout(
    availableWidth: 160,
    labelWidth: 60,
    valueWidth: 240,
  );
  check(
    narrow.stacked && narrow.scrollValue,
    'Narrow panels scroll complete values instead of splitting names or addresses',
  );
  final scaled = networkDetailLayout(
    availableWidth: 328,
    labelWidth: 96,
    valueWidth: 480,
  );
  check(
    scaled.stacked && scaled.scrollValue,
    'Large text remains readable without downscaling',
  );
  final limit = networkDetailLayout(
    availableWidth: 300,
    labelWidth: 48,
    valueWidth: 240,
  );
  check(
    !limit.stacked && !limit.scrollValue,
    'An exactly fitting label, gap and value fit the same line',
  );
  stdout.writeln(
    'Network detail available-width, full-line IPv6, narrow-screen and large-text checks passed.',
  );
}
