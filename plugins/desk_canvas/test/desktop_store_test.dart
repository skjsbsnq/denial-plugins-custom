// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone Dart regression checks: no Flutter engine or desktop UI required.
import 'dart:async';
import 'dart:io';

import 'package:desk_canvas/src/desktop_store.dart';
import 'package:desk_canvas/src/rename_no_replace.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> fails(Future<void> Function() action, String message) async {
  try {
    await action();
  } on Object {
    return;
  }
  throw StateError(message);
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for filesystem notification');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

class FakeActions implements FileActions {
  final opened = <String>[], trashed = <String>[];
  @override
  Future<void> open(DesktopItem item) async {
    opened.add(item.path);
  }

  @override
  Future<void> trash(DesktopItem item) async {
    trashed.add(item.path);
  }

  @override
  Future<void> rename(String source, String target) async =>
      renameNoReplace(source, target);
}

Future<void> main() async {
  check(
    desktopDirectory(r'XDG_DESKTOP_DIR = "$HOME/桌面"', '/tmp/home') ==
        '/tmp/home/桌面',
    'XDG whitespace / localized path',
  );
  check(
    desktopDirectory(r'XDG_DESKTOP_DIR="$HOME"', '/tmp/home') == null,
    'Disabled desktop must not expose home',
  );
  check(
    desktopDirectory(r'XDG_DESKTOP_DIR="$HOME/../home"', '/tmp/home') == null,
    'Normalized home must remain disabled',
  );
  check(
    desktopDirectory(r'XDG_DESKTOP_DIR="$(touch /tmp/never)"', '/tmp/home') ==
        null,
    'Never evaluate shell',
  );
  check(
    desktopDirectory(r'XDG_DESKTOP_DIR="/tmp/a\$b"', '/tmp/home') ==
        '/tmp/a\$b',
    'Escaped dollar',
  );
  check(
    desktopDirectory('', '/tmp/home') == '/tmp/home/Desktop',
    'Default desktop',
  );
  check(
    !validFileName('../a') &&
        !validFileName('a\u0000b') &&
        !validFileName('..'),
    'Invalid filename',
  );
  final entry = DesktopEntry.parse(
    '[Desktop Entry]\nType=Application\nName=Plain\nName[zh_CN]=中文\nExec=example %U\n[Desktop Action Test]\nName=Wrong\n',
  );
  check(
    entry.application && entry.name('fallback', 'zh_CN.UTF-8') == '中文',
    'Localized entry / action group separation',
  );
  check(
    displayName('/tmp/Desktop/firefox.desktop', null, 'zh_CN.UTF-8') ==
        'firefox',
    'Shortcut labels never expose the .desktop suffix',
  );
  check(
    displayName('/tmp/Desktop/notes.md', null, 'zh_CN.UTF-8') == 'notes.md',
    'Real files keep their file name',
  );
  check(
    displayName(
          '/tmp/Desktop/firefox.desktop',
          DesktopEntry.parse('[Desktop Entry]\nType=Application\nName=  \n'),
          'zh_CN',
        ) ==
        'firefox',
    'Blank Name falls back to the file stem',
  );
  final many = List.generate(10000, (i) => 'item$i');
  final dense = arrange(many, {}, 10, 20);
  check(
    dense.length == 10000 && dense.values.toSet().length == 10000,
    'dense overflow layout is collision-free',
  );
  check(
    dense[many.last] == const GridSlot(499, 19),
    'overflow remains column-major',
  );
  final arranged = arrange(
    ['a', 'b', 'c'],
    {
      'a': const GridSlot(99, -1),
      'b': const GridSlot(0, 0),
      'c': const GridSlot(0, 0),
    },
    1,
    1,
  );
  check(
    arranged.values.toSet().length == 3 &&
        arranged['b'] == const GridSlot(0, 0),
    'Grid collision / offscreen recovery',
  );
  for (final env in [
    <String, String>{},
    {'HOME': 'relative'},
    {'HOME': '/tmp/test', 'XDG_CONFIG_HOME': 'relative'},
  ]) {
    final invalid = DesktopStore(environment: env, actions: FakeActions());
    await invalid.start();
    check(
      invalid.error != null && !invalid.loading && invalid.items.isEmpty,
      'Invalid environment must fail before filesystem reads',
    );
    await fails(invalid.save, 'Invalid environment cannot save configuration');
    await invalid.dispose();
  }
  final temp = await Directory.systemTemp.createTemp('desk-canvas-test-');
  DesktopStore? store;
  try {
    final config = await Directory('${temp.path}/config').create();
    final desktop = await Directory('${temp.path}/桌面').create();
    final env = {
      'HOME': temp.path,
      'XDG_CONFIG_HOME': config.path,
      'LANG': 'zh_CN.UTF-8',
    };
    final userDirs = File('${config.path}/user-dirs.dirs');
    await userDirs.writeAsString('XDG_DESKTOP_DIR="${desktop.path}"\n');
    final source = File('${desktop.path}/example.desktop');
    await source.writeAsString(
      '[Desktop Entry]\nType=Application\nName=Example\nName[zh_CN]=示例\nExec=example\n',
    );
    await File('${desktop.path}/.hidden').writeAsString('hidden');
    await Directory('${desktop.path}/folder.desktop').create();
    await Link('${desktop.path}/broken').create('${desktop.path}/missing');
    var notifications = 0;
    final fake = FakeActions();
    store = DesktopStore(
      environment: env,
      actions: fake,
      onChanged: () => notifications++,
    );
    await store.start();
    check(
      store.error == null && store.items.length == 3,
      'Initial listing with hidden file and broken link',
    );
    final namedFolder = store.items.firstWhere(
      (i) => i.key == 'folder.desktop',
    );
    check(
      namedFolder.directory &&
          !namedFolder.shortcut &&
          namedFolder.problem == null,
      'A folder ending .desktop remains a folder',
    );
    check(
      store.items.firstWhere((i) => i.shortcut).name == '示例',
      'Localized real .desktop',
    );
    check(
      store.items.firstWhere((i) => i.key == 'broken').problem != null,
      'Broken link state',
    );
    await File('${desktop.path}/later.txt').writeAsString('later');
    await until(() => store!.items.any((i) => i.key == 'later.txt'));
    await store.createFolder('新建');
    final folder = store.items.firstWhere((i) => i.key == '新建');
    store.positions[folder.key] = const GridSlot(1, 2);
    await store.rename(folder, '改名');
    check(
      await Directory('${desktop.path}/改名').exists() &&
          store.positions['改名'] == const GridSlot(1, 2),
      'Real rename preserves position',
    );
    await File('${desktop.path}/taken').writeAsString('keep');
    final normal = store.items.firstWhere((i) => i.key == 'later.txt');
    await fails(
      () => store!.rename(normal, 'taken'),
      'Never overwrite existing file',
    );
    check(
      await File('${desktop.path}/taken').readAsString() == 'keep' &&
          await File(normal.path).exists(),
      'Existing file unchanged',
    );
    // Atomic backend itself rejects a destination, independently of the UI precheck.
    await fails(
      () => fake.rename(normal.path, '${desktop.path}/taken'),
      'Atomic no-replace is required',
    );
    check(
      await File('${desktop.path}/taken').readAsString() == 'keep' &&
          await File(normal.path).exists(),
      'No-replace kept both files',
    );
    final big = File('${desktop.path}/large.desktop');
    await big.writeAsString('x' * 262145);
    await store.refresh();
    check(
      store.items.firstWhere((i) => i.key == 'large.desktop').problem != null,
      'Oversized entries isolated',
    );
    await fails(
      () => readBounded(big, 262144),
      'Bounded read must reject too large files',
    );
    store.iconSize = 64;
    store.showHidden = true;
    await store.save();
    await store.dispose();
    store = DesktopStore(
      environment: env,
      actions: fake,
      onChanged: () => notifications++,
    );
    await store.start();
    check(
      store.iconSize == 64 &&
          store.showHidden &&
          store.positions['改名'] == const GridSlot(1, 2),
      'Persisted versioned preferences',
    );
    await userDirs.writeAsString('XDG_DESKTOP_DIR="\u0000"');
    await until(() => store!.error != null);
    await userDirs.writeAsString('XDG_DESKTOP_DIR="${desktop.path}"');
    await until(() => store!.error == null);
    await desktop.rename('${temp.path}/old-desktop');
    await until(() => store!.error != null);
    await desktop.create();
    await File('${desktop.path}/reborn').writeAsString('hi');
    await until(() => store!.items.any((i) => i.key == 'reborn'));
    final stale = store.items.single;
    final other = await Directory('${temp.path}/Other').create();
    await userDirs.writeAsString('XDG_DESKTOP_DIR="${other.path}"');
    await store.refresh();
    await fails(
      () => store!.validateItem(stale),
      'Stale old-directory items cannot be operated',
    );
    final before = notifications;
    final loading = store.refresh();
    await store.dispose();
    await loading;
    await File('${other.path}/after-dispose').writeAsString('x');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    check(notifications == before, 'No notifications after disposal');
    check(
      fake.opened.isEmpty && fake.trashed.isEmpty,
      'Tests never launch or trash files',
    );
    stdout.writeln(
      'PASS: XDG, entry parsing, layout collision, file events, rename no-replace, preferences, invalid config recovery, directory recreation, stale items and disposal.',
    );
  } finally {
    await store?.dispose();
    await temp.delete(recursive: true);
  }
}
