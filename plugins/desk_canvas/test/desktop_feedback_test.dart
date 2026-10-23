// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:math';

import 'package:desk_canvas/src/hover_feedback.dart';
import 'package:desk_canvas/src/desktop_store.dart';
import 'package:desk_canvas/src/desktop_drag_layout.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, GridSlot> previousDrop(
  Map<String, GridSlot> layout,
  List<String> keys,
  int dx,
  int dy,
  int columns,
  int rows,
) {
  final moving = {
    for (final key in keys)
      if (layout[key] != null) key: layout[key]!,
  };
  final occupied = {
    for (final entry in layout.entries)
      if (!keys.contains(entry.key)) entry.value,
  };
  final result = <String, GridSlot>{};
  for (final entry in moving.entries) {
    var slot = GridSlot(
      (entry.value.column + dx).clamp(0, columns - 1),
      (entry.value.row + dy).clamp(0, rows - 1),
    );
    if (occupied.contains(slot)) {
      var index = 0;
      while (occupied.contains(GridSlot(index ~/ rows, index % rows))) {
        index++;
      }
      slot = GridSlot(index ~/ rows, index % rows);
    }
    occupied.add(slot);
    result[entry.key] = slot;
  }
  return result;
}

void main() {
  final feedback = DesktopHoverFeedback();
  check(feedback.update(inside: true) && feedback.hovered, 'initial hover');
  feedback.reset();
  check(!feedback.hovered, 'popup/launch reset left a hover');
  check(
    !feedback.update(inside: true) && !feedback.hovered,
    'synthetic entry restored stale hover',
  );
  check(!feedback.update(inside: false), 'reset exit changed idle state');
  check(!feedback.update(inside: true), 'focus return restored stale hover');
  check(
    feedback.update(inside: true, moved: true) && feedback.hovered,
    'real movement did not restore hover',
  );
  check(
    !feedback.update(inside: true, moved: true),
    'unchanged hover should not rebuild',
  );
  check(
    feedback.update(inside: false) && !feedback.hovered,
    'exit did not clear hover',
  );

  final random = Random(27);
  for (var trial = 0; trial < 100; trial++) {
    final count = 100 + random.nextInt(300);
    final rows = 3 + random.nextInt(12), columns = 3 + random.nextInt(10);
    final keys = List.generate(count, (i) => 'item$i');
    final shuffled = keys.toList()..shuffle(random);
    final layout = {
      for (var i = 0; i < keys.length; i++)
        keys[i]: GridSlot(i ~/ rows, i % rows),
    };
    final moving = shuffled.take(1 + random.nextInt(count)).toList();
    final dx = random.nextInt(15) - 7, dy = random.nextInt(15) - 7;
    final old = previousDrop(layout, moving, dx, dy, columns, rows);
    final current = moveDesktopItems(layout, moving, dx, dy, columns, rows);
    check(
      current.length == old.length &&
          old.entries.every((e) => current[e.key] == e.value),
      'group collision policy changed',
    );
  }
  stdout.writeln(
    'PASS: transient hover reset, synthetic entry suppression, real movement recovery and identical group-drop layout.',
  );
}
