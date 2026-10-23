// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:math';

import 'package:desk_canvas/src/desktop_store.dart';
import 'package:desk_canvas/src/desktop_viewport.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  const cellHeight = 98.0, rows = 11;
  final random = Random(42);
  final items = List.generate(
    5000,
    (i) => DesktopItem(
      path: '/temporary/item$i',
      name: 'item$i',
      directory: false,
    ),
  );
  final slots = List.generate(
    items.length,
    (i) => GridSlot(i ~/ rows, i % rows),
  )..shuffle(random);
  final layout = {
    for (var i = 0; i < items.length; i++) items[i].key: slots[i],
  };
  final index = DesktopViewportIndex(items, layout);
  check(index.columnCount == 455, 'incorrect content width');
  final pins = {items.first.key, items.last.key, 'missing'};
  for (final cellWidth in [84.0, 100.0, 132.0, 100.5]) {
    for (final offset in [
      -150.0,
      0.0,
      0.1,
      99.0,
      100.0,
      100.1,
      425.5,
      32500.0,
      45500.0,
    ]) {
      for (final width in [1.0, 100.0, 340.4, 1024.0]) {
        for (final pinned in [<String>{}, pins]) {
          final viewport = (
            left: offset - cellWidth,
            right: offset + width + cellWidth,
          );
          final previous = items
              .where((item) {
                final slot = layout[item.key]!;
                final left = slot.column * cellWidth;
                final top = slot.row * cellHeight;
                return pinned.contains(item.key) ||
                    (left < viewport.right &&
                        left + cellWidth > viewport.left &&
                        top < rows * cellHeight);
              })
              .map((item) => item.key)
              .join(',');
          final current = index
              .visible(offset, width, cellWidth, pinned: pinned)
              .map((item) => item.key)
              .join(',');
          check(
            current == previous,
            'viewport changed at offset $offset / width $width',
          );
        }
      }
    }
  }
  check(index.visible(double.nan, 300, 100).isEmpty, 'nonfinite offset');
  check(index.visible(0, 300, 0).isEmpty, 'invalid cell width');

  final original = <DesktopItem>[
    const DesktopItem(
      path: '/temporary/a.desktop',
      name: 'App',
      directory: false,
      entry: DesktopEntry({
        'Type': 'Application',
        'Exec': 'app',
        'Icon': 'app',
      }),
    ),
  ];
  DesktopItem replacement({
    String name = 'App',
    String path = '/temporary/a.desktop',
    String? problem,
    bool directory = false,
    Map<String, String>? fields,
  }) => DesktopItem(
    path: path,
    name: name,
    directory: directory,
    problem: problem,
    entry: DesktopEntry(
      fields ?? {'Icon': 'app', 'Exec': 'app', 'Type': 'Application'},
    ),
  );
  check(
    identical(reuseDesktopItems(original, [replacement()]), original),
    'unchanged list should be retained',
  );
  for (final changed in [
    replacement(name: 'Renamed'),
    replacement(path: '/temporary/b.desktop'),
    replacement(problem: 'unreadable'),
    replacement(directory: true),
    replacement(
      fields: {'Type': 'Application', 'Exec': 'new-command', 'Icon': 'app'},
    ),
  ]) {
    check(
      identical(reuseDesktopItems(original, [changed]).single, changed),
      'changed metadata was hidden',
    );
  }
  final extra = replacement(path: '/temporary/c.desktop');
  final extended = reuseDesktopItems(original, [replacement(), extra]);
  check(
    identical(extended.first, original.first) &&
        identical(extended.last, extra),
    'unchanged entry was rebuilt',
  );
  check(reuseDesktopItems(original, []).isEmpty, 'deleted entry was retained');
  stdout.writeln(
    'PASS: indexed viewport matches full scans, edge columns, stacking order, dragged entries and metadata invalidation.',
  );
}
