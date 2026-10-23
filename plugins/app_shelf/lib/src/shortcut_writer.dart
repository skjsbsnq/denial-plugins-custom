// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

enum ShortcutStatus { created, alreadyExists, conflict }

class ShortcutResult {
  const ShortcutResult(this.status, this.path);
  final ShortcutStatus status;
  final String path;
}

/// Resolves user-dirs as data, never evaluating shell substitutions.
Future<Directory> resolveDesktopDirectory(
  Map<String, String> environment,
) async {
  final home = environment['HOME'];
  if (home == null || !home.startsWith('/')) {
    throw const FormatException('HOME must be an absolute path');
  }
  final config = environment['XDG_CONFIG_HOME'] ?? '$home/.config';
  if (!config.startsWith('/')) {
    throw const FormatException('Invalid config path');
  }
  final file = File('$config/user-dirs.dirs');
  String path = '$home/Desktop';
  if (await file.exists()) {
    if (await file.length() > 65536) {
      throw const FormatException('user-dirs.dirs is too large');
    }
    final lines = const LineSplitter().convert(
      utf8.decode(await _readBounded(file, 65536)),
    );
    for (final line in lines) {
      if (!RegExp(r'^\s*XDG_DESKTOP_DIR\s*=').hasMatch(line)) continue;
      final match = RegExp(
        r'^\s*XDG_DESKTOP_DIR\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$',
      ).firstMatch(line);
      if (match == null) {
        throw const FormatException('Invalid desktop directory');
      }
      var value = match[1]!;
      if (value.startsWith(r'$HOME/')) {
        value = home + value.substring(5);
      } else if (value == r'$HOME') {
        value = home;
      } else if (value.startsWith(r'${HOME}/')) {
        value = home + value.substring(7);
      }
      if (RegExp(r'(?<!\\)[$`]').hasMatch(value)) {
        throw const FormatException('Unsupported directory expansion');
      }
      value = value.replaceAllMapped(RegExp(r'\\([\\"$`])'), (m) => m[1]!);
      if (value.contains('\\') ||
          !value.startsWith('/') ||
          value.contains('\u0000')) {
        throw const FormatException('Invalid desktop path');
      }
      path = value;
    }
  }
  final uri = Directory(path).absolute.uri.normalizePath();
  if (uri.path == Directory(home).absolute.uri.normalizePath().path) {
    throw const FormatException('Desktop directory is disabled');
  }
  final normalized = Directory.fromUri(uri).path;
  return Directory(
    normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized,
  );
}

/// Writes exact entry bytes, without interpreting Exec or touching the source.
class ShortcutWriter {
  ShortcutWriter({
    Map<String, String>? environment,
    Future<ProcessResult> Function(String, List<String>)? runCommand,
  }) : environment = Map.unmodifiable(environment ?? Platform.environment),
       _runCommand =
           runCommand ??
           ((command, arguments) => Process.run(command, arguments));
  final Future<ProcessResult> Function(String, List<String>) _runCommand;
  final Map<String, String> environment;
  final Set<String> _pending = {};

  Future<ShortcutResult> send(String sourcePath) async {
    if (!_pending.add(sourcePath)) {
      throw StateError('Shortcut creation in progress');
    }
    try {
      final source = File(sourcePath);
      if (!source.isAbsolute || !sourcePath.endsWith('.desktop')) {
        throw const FormatException('Invalid application entry path');
      }
      if (await source.length() > 256 * 1024) {
        throw const FormatException('Application entry is too large');
      }
      final bytes = await _readBounded(source, 256 * 1024);
      final text = utf8.decode(bytes);
      if (bytes.length > 256 * 1024 ||
          text.contains('\u0000') ||
          !RegExp(r'^\[Desktop Entry\]\r?$', multiLine: true).hasMatch(text)) {
        throw const FormatException('Invalid desktop entry');
      }
      final directory = await resolveDesktopDirectory(environment);
      await directory.create(recursive: true);
      final name = source.uri.pathSegments.last;
      final target = File.fromUri(
        directory.uri.resolve(Uri.encodeComponent(name)),
      );
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        if (type == FileSystemEntityType.file &&
            await target.length() <= 256 * 1024) {
          final existing = await _readBounded(target, 256 * 1024);
          if (_equal(existing, bytes)) {
            return ShortcutResult(ShortcutStatus.alreadyExists, target.path);
          }
        }
        return ShortcutResult(ShortcutStatus.conflict, target.path);
      }
      // A private same-filesystem staging directory and exclusive hard link
      // publish complete bytes atomically without replacing a concurrent file.
      final staging = await directory.createTemp('.app-shelf-');
      try {
        final staged = File('${staging.path}/entry');
        await staged.writeAsBytes(bytes, flush: true);
        final result = await _runCommand('ln', [
          '-T',
          '--',
          staged.path,
          target.path,
        ]);
        if (result.exitCode != 0) {
          if (await FileSystemEntity.type(target.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return ShortcutResult(ShortcutStatus.conflict, target.path);
          }
          throw FileSystemException(
            'Cannot publish shortcut: ${result.stderr}',
            target.path,
          );
        }
      } finally {
        await staging.delete(recursive: true);
      }
      return ShortcutResult(ShortcutStatus.created, target.path);
    } finally {
      _pending.remove(sourcePath);
    }
  }
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<List<int>> _readBounded(File file, int limit) async {
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, limit + 1)) {
    bytes.addAll(chunk);
    if (bytes.length > limit) {
      throw const FormatException('File exceeds size limit');
    }
  }
  return bytes;
}
