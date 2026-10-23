// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'desktop_store.dart';

/// A layout snapshot indexed by column. Scrolling visits only nearby columns,
/// preserving the original stacking order and keeping dragged entries mounted.
class DesktopViewportIndex {
  DesktopViewportIndex(List<DesktopItem> items, Map<String, GridSlot> layout)
    : _items = List.unmodifiable(items) {
    for (var i = 0; i < items.length; i++) {
      final key = items[i].key;
      final slot = layout[key];
      if (slot == null) continue;
      (_columns[slot.column] ??= []).add(i);
      _byKey[key] = i;
      columnCount = math.max(columnCount, slot.column + 1);
    }
  }
  final List<DesktopItem> _items;
  final _columns = <int, List<int>>{};
  final _byKey = <String, int>{};
  int columnCount = 0;

  List<DesktopItem> visible(
    double offset,
    double width,
    double cellWidth, {
    Set<String> pinned = const {},
  }) {
    if (!offset.isFinite ||
        !width.isFinite ||
        !cellWidth.isFinite ||
        width <= 0 ||
        cellWidth <= 0) {
      return const [];
    }
    // One extra column on either side, exactly matching the previous viewport.
    final first = math.max(0, ((offset - cellWidth) / cellWidth).floor());
    final last = math.min(
      columnCount - 1,
      ((offset + width + cellWidth) / cellWidth).ceil() - 1,
    );
    final indices = <int>{};
    for (var column = first; column <= last; column++) {
      indices.addAll(_columns[column] ?? const []);
    }
    for (final key in pinned) {
      final index = _byKey[key];
      if (index != null) indices.add(index);
    }
    final ordered = indices.toList()..sort();
    return [for (final index in ordered) _items[index]];
  }
}
