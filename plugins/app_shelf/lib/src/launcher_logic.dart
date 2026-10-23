// SPDX-License-Identifier: GPL-3.0-or-later
/// Stable recent-first ordering, with text search preserving host catalog order.
List<T> filterApplications<T>(
  List<T> applications,
  List<String> recents,
  String query,
  String Function(T) id,
  String Function(T) name,
  String Function(T) searchableText,
) {
  final needle = query.trim().toLowerCase();
  final filtered = applications
      .where(
        (app) =>
            needle.isEmpty ||
            searchableText(app).contains(needle) ||
            name(app).toLowerCase().contains(needle),
      )
      .toList();
  if (needle.isEmpty) {
    final ranks = <String, int>{};
    for (var i = 0; i < recents.length; i++) {
      ranks.putIfAbsent(recents[i], () => i);
    }
    filtered.sort((a, b) {
      final order = (ranks[id(a)] ?? recents.length).compareTo(
        ranks[id(b)] ?? recents.length,
      );
      return order != 0
          ? order
          : name(a).toLowerCase().compareTo(name(b).toLowerCase());
    });
  }
  return filtered;
}

int moveSelection(int selected, int delta, int count) =>
    count == 0 ? 0 : (selected + delta).clamp(0, count - 1);
double? revealSelection(
  int selected,
  int columns,
  double rowHeight,
  double offset,
  double viewport,
  double maxOffset,
) {
  final y = (selected ~/ columns) * rowHeight;
  if (y < offset) return y.clamp(0, maxOffset);
  if (y + rowHeight > offset + viewport) {
    return (y + rowHeight - viewport).clamp(0, maxOffset);
  }
  return null;
}

/// Header rows have no application index; navigation only visits applications.
class ApplicationRow {
  const ApplicationRow({this.applicationIndex, this.heading});
  final int? applicationIndex;
  final String? heading;
}

/// Catalog data is immutable until the host changes its application snapshot.
/// Normalize and sort once; keystrokes only filter the original catalog order.
class ApplicationCatalog<T> {
  ApplicationCatalog(
    List<T> source,
    String Function(T) id,
    String Function(T) name,
    String Function(T) searchable,
  ) {
    for (var i = 0; i < source.length; i++) {
      final app = source[i];
      final key = id(app);
      final label = name(app);
      final entry = _ApplicationEntry(
        app,
        key,
        label.toLowerCase(),
        searchable(app),
        applicationHeading(label),
        i,
      );
      _entries.add(entry);
      _byId[key] = app;
    }
    final alphabetical = _entries.toList()
      ..sort((a, b) {
        final group = a.heading.compareTo(b.heading);
        if (group != 0) return group;
        final label = a.name.compareTo(b.name);
        return label != 0 ? label : a.sourceIndex.compareTo(b.sourceIndex);
      });
    _all = List.unmodifiable(alphabetical.map((entry) => entry.app));
    final rows = <ApplicationRow>[];
    final applicationRows = <int>[];
    final applicationRowById = <String, int>{};
    final headingRows = <String, int>{};
    String? previous;
    for (var i = 0; i < alphabetical.length; i++) {
      final heading = alphabetical[i].heading;
      if (heading != previous) {
        headingRows[heading] = rows.length;
        rows.add(ApplicationRow(heading: heading));
        previous = heading;
      }
      applicationRows.add(rows.length);
      applicationRowById[alphabetical[i].id] = rows.length;
      rows.add(ApplicationRow(applicationIndex: i));
    }
    _allRows = List.unmodifiable(rows);
    _allApplicationRows = List.unmodifiable(applicationRows);
    _allApplicationRowById = Map.unmodifiable(applicationRowById);
    _allHeadingRows = Map.unmodifiable(headingRows);
  }
  final _entries = <_ApplicationEntry<T>>[];
  final _byId = <String, T>{};
  late final List<T> _all;
  late final List<ApplicationRow> _allRows;
  late final List<int> _allApplicationRows;
  late final Map<String, int> _allApplicationRowById;
  late final Map<String, int> _allHeadingRows;

  ApplicationIndex<T> query(List<String> recentIds, String query) {
    final recent = <T>[];
    final seen = <String>{};
    for (final key in recentIds) {
      if (seen.add(key) && _byId.containsKey(key)) recent.add(_byId[key] as T);
      if (recent.length == 9) break;
    }
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return ApplicationIndex._(
        _all,
        recent,
        _allRows,
        _allApplicationRows,
        _allApplicationRowById,
        _allHeadingRows,
      );
    }
    final applications = <T>[];
    final applicationRowById = <String, int>{};
    for (final entry in _entries) {
      if (entry.searchable.contains(needle) || entry.name.contains(needle)) {
        applicationRowById[entry.id] = applications.length;
        applications.add(entry.app);
      }
    }
    return ApplicationIndex._(
      applications,
      recent,
      List.generate(
        applications.length,
        (i) => ApplicationRow(applicationIndex: i),
      ),
      List.generate(applications.length, (i) => i),
      Map.unmodifiable(applicationRowById),
      const {},
    );
  }
}

class _ApplicationEntry<T> {
  const _ApplicationEntry(
    this.app,
    this.id,
    this.name,
    this.searchable,
    this.heading,
    this.sourceIndex,
  );
  final T app;
  final String id, name, searchable, heading;
  final int sourceIndex;
}

class ApplicationIndex<T> {
  factory ApplicationIndex(
    List<T> source,
    List<String> recentIds,
    String query,
    String Function(T) id,
    String Function(T) name,
    String Function(T) searchable,
  ) => ApplicationCatalog(source, id, name, searchable).query(recentIds, query);

  ApplicationIndex._(
    this.applications,
    this.recent,
    this.rows,
    this.applicationRows,
    this.applicationRowById,
    this.headingRows,
  );
  final List<T> applications;
  final List<T> recent;
  final List<ApplicationRow> rows;
  final List<int> applicationRows;
  final Map<String, int> applicationRowById;
  final Map<String, int> headingRows;
}

String applicationHeading(String name) {
  final first = name.trim().toUpperCase();
  return first.isNotEmpty && _latinInitial.hasMatch(first) ? first[0] : '#';
}

final _latinInitial = RegExp(r'^[A-Z]');
