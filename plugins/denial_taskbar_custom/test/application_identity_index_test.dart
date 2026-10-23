import 'dart:io';

import 'package:denial_taskbar_custom/src/application_identity_index.dart';
import 'package:denial_taskbar_custom/src/taskbar_preferences.dart';
import 'package:denial_taskbar_custom/src/window_groups.dart';

typedef App = ({String id, String appId, List<String> aliases});
typedef Window = ({int id, String app});

void main() {
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  var catalogReads = 0;
  final index = ApplicationIdentityIndex<App>(
    idOf: (app) => app.id,
    appIdOf: (app) {
      catalogReads++;
      return app.appId;
    },
    aliasesOf: (app) => app.aliases,
  );
  const editor = (
    id: 'desktop:editor.desktop',
    appId: 'Editor.desktop',
    aliases: ['editor-class', ' Editor-Class.desktop ', 'shared'],
  );
  const browser = (
    id: 'desktop:browser.desktop',
    appId: 'Browser',
    aliases: ['shared', 'editor'],
  );
  const duplicateExact = (
    id: 'desktop:duplicate',
    appId: ' EDITOR ',
    aliases: <String>[],
  );
  const pins = [
    PinnedApplication(id: 'pin:old', appId: 'old.desktop', name: 'Old'),
    PinnedApplication(id: 'pin:duplicate', appId: 'OLD', name: 'Duplicate'),
    PinnedApplication(id: 'pin:editor', appId: 'editor', name: 'Editor'),
    PinnedApplication(id: 'pin:shared', appId: 'shared', name: 'Shared'),
  ];
  final catalog = List<App>.unmodifiable([editor, browser, duplicateExact]);
  index.update(catalog, pins);
  check(index.applicationFor(' editor.desktop ') == editor, 'Exact ID first');
  check(
    index.applicationFor('editor-class.desktop') == editor,
    'Duplicate aliases within one entry must remain unique',
  );
  check(index.applicationFor('shared') == null, 'Shared alias is ambiguous');
  check(index.groupIdentity('EDITOR') == editor.id, 'Catalog wins over pin');
  check(index.groupIdentity('OLD') == 'pin:old', 'First matching pin wins');
  check(
    index.groupIdentity('shared') == 'pin:shared',
    'Ambiguous catalog alias falls back to pin',
  );
  check(
    index.groupIdentity(' Unknown.desktop ') == ' Unknown.desktop ',
    'Unknown identities retain their original spelling',
  );
  check(
    index.applicationForGroup('app:desktop:editor') == editor,
    'Group keys normalize launch IDs',
  );

  final groups = WindowGroups<Window>(
    idOf: (window) => window.id,
    appOf: (window) => index.groupIdentity(window.app),
  );
  final grouped = groups.update([
    (id: 1, app: 'editor-class'),
    (id: 2, app: 'Browser.desktop'),
    (id: 3, app: 'EDITOR'),
  ]);
  check(
    grouped['app:desktop:editor']!.map((window) => window.id).join(',') ==
        '1,3',
    'Exact and unique alias windows must share their launch group',
  );

  final readsAfterIndex = catalogReads;
  for (var i = 0; i < 100; i++) {
    index.update(catalog, pins);
    index.applicationFor('editor-class');
    index.applicationForGroup('app:desktop:browser');
    index.groupIdentity('unknown');
  }
  check(catalogReads == readsAfterIndex, 'Window updates must reuse catalog');

  index.update(catalog, const []);
  check(index.groupIdentity('old') == 'old', 'Removed pins must be forgotten');
  check(catalogReads == readsAfterIndex, 'Pin changes must reuse catalog');

  // Replacing a snapshot must clear ambiguities, removed IDs and group entries.
  index.update(List<App>.unmodifiable([browser]), const []);
  check(index.applicationFor('shared') == browser, 'Alias becomes unique');
  check(
    index.applicationFor('editor') == browser,
    'Removed exact ID uses alias',
  );
  check(index.applicationForGroup('app:desktop:editor') == null, 'Stale group');
  check(index.groupIdentity('editor-class') == 'editor-class', 'Stale alias');

  index.update(List<App>.unmodifiable([browser, browser]), const []);
  check(
    index.applicationFor('shared') == null,
    'Separate catalog occurrences count as separate alias matches',
  );
  check(
    index.applicationFor('browser') == browser,
    'Duplicate exact stays first',
  );

  const duplicateGroup = (
    id: ' DESKTOP:Browser.desktop ',
    appId: 'Other',
    aliases: <String>[],
  );
  index.update(List<App>.unmodifiable([browser, duplicateGroup]), const []);
  check(
    index.applicationForGroup('app:desktop:browser') == browser,
    'First normalized launch ID wins',
  );
  stdout.writeln('Application identity index and invalidation checks passed.');
}
