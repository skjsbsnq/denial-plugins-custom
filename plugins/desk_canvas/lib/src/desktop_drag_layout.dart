// SPDX-License-Identifier: GPL-3.0-or-later
import 'desktop_store.dart';

/// Same collision policy and group order as a single-item drop, with one
/// advancing free-slot cursor instead of restarting its search per item.
Map<String, GridSlot> moveDesktopItems(
  Map<String, GridSlot> layout,
  Iterable<String> movingKeys,
  int dx,
  int dy,
  int columns,
  int rows,
) {
  final keys = movingKeys.toSet();
  final occupied = {
    for (final entry in layout.entries)
      if (!keys.contains(entry.key)) entry.value,
  };
  final result = <String, GridSlot>{};
  var freeIndex = 0;
  for (final key in keys) {
    final original = layout[key];
    if (original == null) continue;
    var slot = GridSlot(
      (original.column + dx).clamp(0, columns - 1),
      (original.row + dy).clamp(0, rows - 1),
    );
    if (occupied.contains(slot)) {
      while (occupied.contains(GridSlot(freeIndex ~/ rows, freeIndex % rows))) {
        freeIndex++;
      }
      slot = GridSlot(freeIndex ~/ rows, freeIndex % rows);
    }
    occupied.add(slot);
    result[key] = slot;
  }
  return result;
}
