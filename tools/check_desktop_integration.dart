// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone, headless integration check. All writes stay inside a temp folder.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../plugins/app_shelf/lib/src/shortcut_writer.dart';
import '../plugins/desk_canvas/lib/src/desktop_store.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> eventually(bool Function() ready, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) throw StateError(message);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp(
    'personal-desktop-integration-',
  );
  DesktopStore? store;
  try {
    final home = await Directory('${temporary.path}/用户 home%').create();
    final config = await Directory('${home.path}/config').create();
    final desktop = await Directory('${home.path}/桌面 空间%').create();
    final sourceDirectory = await Directory('${temporary.path}/apps').create();
    final userDirs = File('${config.path}/user-dirs.dirs');
    await userDirs.writeAsString(
      r'XDG_DESKTOP_DIR="$HOME/桌面 空间%"'
      '\n',
    );
    final environment = <String, String>{
      'HOME': home.path,
      'XDG_CONFIG_HOME': config.path,
      'LANG': 'zh_CN.UTF-8',
    };
    store = DesktopStore(environment: environment);
    await store.start();
    check(store.error == null, 'Initial desktop directory must load.');
    check(store.items.isEmpty, 'Fixture desktop must start empty.');

    final source = File('${sourceDirectory.path}/org.example.测试 % App.desktop');
    final bytes = utf8.encode(
      '[Desktop Entry]\r\n'
      'Type=Application\r\n'
      'Name=Example Application\r\n'
      'Name[zh_CN]=测试应用\r\n'
      'Icon=application-default\r\n'
      'Exec=/usr/bin/true %U\r\n'
      'Actions=NewWindow;\r\n'
      '[Desktop Action NewWindow]\r\n'
      'Name=New Window\r\n'
      'Exec=/usr/bin/true --new-window\r\n',
    );
    await source.writeAsBytes(bytes);
    final writer = ShortcutWriter(environment: environment);
    final created = await writer.send(source.path);
    check(
      created.status == ShortcutStatus.created,
      'Shortcut was not created.',
    );
    check(
      File(created.path).parent.path == desktop.path,
      'Shortcut must be published in the actual XDG desktop directory.',
    );
    check(
      base64Encode(await File(created.path).readAsBytes()) ==
          base64Encode(bytes),
      'Sending must preserve every desktop-entry byte and action.',
    );
    await eventually(
      () => store!.items.any((item) => item.path == created.path),
      'Desk Canvas did not discover the shortcut through directory events.',
    );
    final item = store.items.singleWhere((item) => item.path == created.path);
    check(item.shortcut, 'Published file was not recognized as a shortcut.');
    check(
      item.problem == null,
      'Published shortcut was rejected: ${item.problem}',
    );
    check(item.name == '测试应用', 'Localized shortcut name was lost.');
    final duplicate = await writer.send(source.path);
    check(
      duplicate.status == ShortcutStatus.alreadyExists,
      'Sending identical content must not create duplicates.',
    );
    await source.writeAsString(
      '[Desktop Entry]\nType=Application\nName=Changed\nExec=/usr/bin/true\n',
    );
    final conflict = await writer.send(source.path);
    check(
      conflict.status == ShortcutStatus.conflict,
      'Changed source must not overwrite a desktop entry without confirmation.',
    );
    check(
      base64Encode(await File(created.path).readAsBytes()) ==
          base64Encode(bytes),
      'A conflicting send changed the existing desktop file.',
    );
    await File(created.path).delete();
    await eventually(
      () => store!.items.every((item) => item.path != created.path),
      'Removing a desktop shortcut must remove its icon through file events.',
    );
    check(
      await source.exists(),
      'Removing a shortcut must preserve its source.',
    );

    await userDirs.writeAsString(
      r'XDG_DESKTOP_DIR="$HOME"'
      '\n',
    );
    await eventually(
      () => store!.error != null && store.items.isEmpty,
      'An explicitly disabled desktop must not expose the home directory.',
    );
    var rejected = false;
    try {
      await writer.send(source.path);
    } on Object {
      rejected = true;
    }
    check(
      rejected,
      'Shortcut writer must respect a disabled desktop directory.',
    );
    await userDirs.delete();
    final fallback = await writer.send(source.path);
    check(
      fallback.path == '${home.path}/Desktop/${source.uri.pathSegments.last}',
      'Missing user-dirs configuration must use the same fallback in both plugins.',
    );
    await eventually(
      () => store!.items.any((item) => item.path == fallback.path),
      'Desk Canvas did not discover a newly created fallback desktop directory.',
    );
    await userDirs.writeAsString('x' * 65537);
    await eventually(
      () => store!.error != null,
      'Oversized directory configuration must produce an error.',
    );
    await userDirs.writeAsString(r'XDG_DESKTOP_DIR="$HOME/Desktop"' '\n');
    await eventually(
      () => store!.error == null &&
          store.items.any((item) => item.path == fallback.path),
      'Fixing invalid configuration must recover through events without manual refresh.',
    );
    await Directory('${home.path}/Desktop').delete(recursive: true);
    await eventually(
      () => store!.error != null && store.items.isEmpty,
      'Removing the active desktop directory must clear stale icons.',
    );
    final restored = await writer.send(source.path);
    await eventually(
      () => store!.error == null &&
          store.items.any((item) => item.path == restored.path),
      'Recreating the active desktop directory must restore directory watching.',
    );
    final renameSource = File('${temporary.path}/rename-source');
    final renameTarget = File('${temporary.path}/rename-target');
    await renameSource.writeAsString('source');
    await renameTarget.writeAsString('keep-existing');
    rejected = false;
    try {
      await const GioFileActions().rename(renameSource.path, renameTarget.path);
    } on Object {
      rejected = true;
    }
    check(rejected, 'The real rename backend must reject an existing target.');
    check(
      await renameSource.readAsString() == 'source' &&
          await renameTarget.readAsString() == 'keep-existing',
      'Rename conflict must preserve both source and existing target bytes.',
    );
    final freshTarget = '${temporary.path}/renamed-file';
    await const GioFileActions().rename(renameSource.path, freshTarget);
    check(
      !await renameSource.exists() &&
          await File(freshTarget).readAsString() == 'source',
      'The real rename backend must still rename to an unused path.',
    );
    await store.dispose();
    store = null;
    stdout.writeln(
      'PASS: shortcut bytes, localized discovery, duplicate/conflict handling, XDG fallback/error recovery, directory recreation and real no-overwrite renames. No applications were launched.',
    );
  } finally {
    await store?.dispose();
    await temporary.delete(recursive: true);
  }
}
