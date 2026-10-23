// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone Dart regression checks: no engine or desktop session required.
import 'dart:io';

import 'package:app_shelf/src/shortcut_writer.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('app-shelf-test-');
  try {
    final config = await Directory('${root.path}/config').create();
    final env = {'HOME': root.path, 'XDG_CONFIG_HOME': config.path};
    final dirs = File('${config.path}/user-dirs.dirs');
    await dirs.writeAsString(r'XDG_DESKTOP_DIR="$HOME/桌 面%"');
    final resolved = await resolveDesktopDirectory(env);
    check(resolved.path == '${root.path}/桌 面%', 'Unicode XDG directory');
    final source = File('${root.path}/测试 % name.desktop');
    const text =
        '[Desktop Entry]\nType=Application\nName=Example\nName[zh_CN]=测试\nExec=example --flag %U\nActions=New;\n\n[Desktop Action New]\nExec=example --new\n';
    await source.writeAsString(text);
    final writer = ShortcutWriter(environment: env);
    final first = await writer.send(source.path);
    check(first.status == ShortcutStatus.created, 'First send creates');
    check(
      first.path == '${resolved.path}/测试 % name.desktop',
      'Preserve filename',
    );
    check(
      await File(first.path).readAsString() == text,
      'Preserve exact content',
    );
    check(
      (await writer.send(source.path)).status == ShortcutStatus.alreadyExists,
      'Duplicate detected',
    );
    await source.writeAsString('$text\n# updated');
    check(
      (await writer.send(source.path)).status == ShortcutStatus.conflict,
      'Update cannot overwrite silently',
    );
    check(
      await File(first.path).readAsString() == text,
      'Conflict preserves target',
    );
    await File(first.path).delete();
    await Link(first.path).create(source.path);
    check(
      (await writer.send(source.path)).status == ShortcutStatus.conflict,
      'Symlink is never overwritten',
    );
    await Link(first.path).delete();
    await Directory(first.path).create();
    check(
      (await writer.send(source.path)).status == ShortcutStatus.conflict,
      'Directory target is never written into',
    );
    check(
      await Directory(first.path).list().isEmpty,
      'Directory remains empty',
    );
    await Directory(first.path).delete();
    await source.writeAsString('bad');
    var rejected = false;
    try {
      await writer.send(source.path);
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Malformed source rejected');
    await source.writeAsString('[Desktop Entry]\n${'x' * (256 * 1024)}');
    rejected = false;
    try {
      await writer.send(source.path);
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Oversized source rejected');
    await dirs.writeAsString(r'XDG_DESKTOP_DIR="$HOME"');
    rejected = false;
    try {
      await resolveDesktopDirectory(env);
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Disabled desktop rejected');
    await dirs.writeAsString(
      r'XDG_DESKTOP_DIR="$(touch /tmp/should-not-exist)"',
    );
    rejected = false;
    try {
      await resolveDesktopDirectory(env);
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Shell expression rejected');
    await dirs.writeAsString(r'XDG_DESKTOP_DIR="$HOME/桌 面%"');
    await source.writeAsString(text);
    final one = writer.send(source.path);
    rejected = false;
    try {
      await writer.send(source.path);
    } on StateError {
      rejected = true;
    }
    check(rejected, 'Repeated send guarded');
    check(
      (await one).status == ShortcutStatus.created,
      'First concurrent send completes',
    );
    await File(first.path).delete();
    final racingWriter = ShortcutWriter(
      environment: env,
      runCommand: (command, args) async {
        await Directory(args.last).create();
        return Process.run(command, args);
      },
    );
    check(
      (await racingWriter.send(source.path)).status == ShortcutStatus.conflict,
      'Directory created after preflight is a conflict',
    );
    check(
      await Directory(first.path).list().isEmpty,
      'Atomic publish never writes entry inside racing directory',
    );
    check(await source.readAsString() == text, 'Race preserves source');
    await Directory(first.path).delete();
    final otherDirectory = await Directory('${root.path}/other').create();
    final racingLinkWriter = ShortcutWriter(
      environment: env,
      runCommand: (command, args) async {
        await Link(args.last).create(otherDirectory.path);
        return Process.run(command, args);
      },
    );
    check(
      (await racingLinkWriter.send(source.path)).status ==
          ShortcutStatus.conflict,
      'Symlink created after preflight is a conflict',
    );
    check(
      await otherDirectory.list().isEmpty,
      'Atomic publish never follows racing directory symlink',
    );
    stdout.writeln('App Shelf shortcut regression checks passed.');
  } finally {
    await root.delete(recursive: true);
  }
}
