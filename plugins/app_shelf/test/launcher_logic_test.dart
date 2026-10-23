// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:app_shelf/src/launcher_logic.dart';

void check(bool value) {
  if (!value) throw StateError('Launcher regression');
}

void main() {
  const apps = ['Bravo', 'Alpha', '中文应用', 'Charlie'];
  List<String> filtered(String query) => filterApplications(
    apps,
    ['Charlie', 'missing', 'Bravo', 'Charlie'],
    query,
    (x) => x,
    (x) => x,
    (x) => x.toLowerCase(),
  );
  check(filtered('').join(',') == 'Charlie,Bravo,Alpha,中文应用');
  check(filtered('  ALP ').single == 'Alpha');
  check(filtered('中文').single == '中文应用');
  check(filtered('none').isEmpty);
  check(moveSelection(1, -5, 4) == 0);
  check(moveSelection(1, 5, 4) == 3);
  check(moveSelection(8, 1, 0) == 0);
  check(revealSelection(7, 3, 118, 0, 236, 1000) == 118);
  check(revealSelection(1, 3, 118, 236, 236, 1000) == 0);
  check(revealSelection(1, 3, 118, 0, 236, 1000) == null);
  check(revealSelection(9, 3, 118, 0, 236, 100) == 100);
  final index = ApplicationIndex(
    ['Zulu', 'Alpha', 'Beta', '中文', '123'],
    ['Beta', 'missing', 'Beta', 'Alpha'],
    '',
    (x) => x,
    (x) => x,
    (x) => x.toLowerCase(),
  );
  check(index.applications.join(',') == '123,中文,Alpha,Beta,Zulu');
  check(index.recent.join(',') == 'Beta,Alpha');
  check(
    index.rows
            .where((r) => r.heading != null)
            .map((r) => r.heading)
            .join(',') ==
        '#,A,B,Z',
  );
  for (var i = 0; i < index.applications.length; i++) {
    check(index.rows[index.applicationRows[i]].applicationIndex == i);
    check(
      index.applicationRowById[index.applications[i]] ==
          index.applicationRows[i],
    );
  }
  for (final entry in index.headingRows.entries) {
    check(index.rows[entry.value].heading == entry.key);
  }
  check(index.applicationRowById['missing'] == null);
  check(index.headingRows['missing'] == null);
  final search = ApplicationIndex(
    apps,
    [],
    'alp',
    (x) => x,
    (x) => x,
    (x) => x.toLowerCase(),
  );
  check(search.applications.single == 'Alpha');
  check(search.rows.single.applicationIndex == 0);
  check(search.applicationRows.single == 0);
  check(search.applicationRowById['Alpha'] == 0);
  check(search.applicationRowById['Bravo'] == null);
  check(search.headingRows.isEmpty);
  var idReads = 0, nameReads = 0, searchReads = 0;
  final catalog = ApplicationCatalog(
    apps,
    (x) {
      idReads++;
      return x;
    },
    (x) {
      nameReads++;
      return x;
    },
    (x) {
      searchReads++;
      return x.toLowerCase();
    },
  );
  final initial = catalog.query(['Bravo'], '');
  final recentsChanged = catalog.query(['Alpha'], '');
  check(identical(initial.applications, recentsChanged.applications));
  check(identical(initial.rows, recentsChanged.rows));
  check(identical(initial.applicationRows, recentsChanged.applicationRows));
  check(
    identical(initial.applicationRowById, recentsChanged.applicationRowById),
  );
  check(identical(initial.headingRows, recentsChanged.headingRows));
  check(recentsChanged.recent.single == 'Alpha');
  for (final query in [' ALP ', '中文', 'none', 'br', '', 'a']) {
    final result = catalog.query([], query);
    if (query.trim().isNotEmpty) {
      check(result.applications.join(',') == filtered(query).join(','));
    }
    for (var i = 0; i < result.applications.length; i++) {
      check(result.rows[result.applicationRows[i]].applicationIndex == i);
      check(
        result.applicationRowById[result.applications[i]] ==
            result.applicationRows[i],
      );
    }
  }
  check(
    idReads == apps.length &&
        nameReads == apps.length &&
        searchReads == apps.length,
  );
  check(
    catalog
            .query(['missing', 'Bravo', 'Bravo', 'Alpha'], '')
            .recent
            .join(',') ==
        'Bravo,Alpha',
  );
  // Remapping follows opaque identity after a catalog reorder or label change;
  // search excludes stale IDs and uses its own ungrouped row positions.
  const original = [(id: 'app-b', name: 'Beta'), (id: 'app-a', name: 'Alpha')];
  const reordered = [(id: 'app-a', name: 'Zulu'), (id: 'app-b', name: 'Beta')];
  ApplicationCatalog<({String id, String name})> prepare(
    List<({String id, String name})> source,
  ) => ApplicationCatalog(source, (a) => a.id, (a) => a.name, (a) => a.name);
  final before = prepare(original).query([], '');
  final afterCatalog = prepare(reordered);
  final after = afterCatalog.query([], '');
  check(before.applicationRowById['app-a'] == 1);
  check(after.applicationRowById['app-a'] == 3);
  check(after.applicationRowById['app-b'] == 1);
  check(after.headingRows['A'] == null && after.headingRows['Z'] == 2);
  final narrowed = afterCatalog.query([], 'beta');
  check(narrowed.applicationRowById['app-b'] == 0);
  check(narrowed.applicationRowById['app-a'] == null);
  check(narrowed.headingRows.isEmpty);
  check(afterCatalog.query([], 'absent').applicationRowById.isEmpty);
  stdout.writeln('App Shelf launcher regression checks passed.');
}
