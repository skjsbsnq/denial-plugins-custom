// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'rename_no_replace.dart';

/// Bounded, non-executing parser for the XDG user directory configuration.
String? desktopDirectory(String source, String home) {
  if (source.contains('\u0000') || !home.startsWith('/')) return null;
  String path = '$home/Desktop';
  for (final line in const LineSplitter().convert(source)) {
    if (!RegExp(r'^\s*XDG_DESKTOP_DIR\s*=').hasMatch(line)) continue;
    final match = RegExp(
      r'^\s*XDG_DESKTOP_DIR\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$',
    ).firstMatch(line);
    if (match == null) return null;
    var value = match[1]!;
    if (value.startsWith(r'$HOME/')) {
      value = home + value.substring(5);
    } else if (value == r'$HOME') {
      value = home;
    } else if (value.startsWith(r'${HOME}/')) {
      value = home + value.substring(7);
    }
    if (RegExp(r'(?<!\\)[$`]').hasMatch(value)) return null;
    value = value.replaceAllMapped(RegExp(r'\\([\\"$`])'), (m) => m[1]!);
    if (value.contains('\\') ||
        !value.startsWith('/') ||
        value.contains('\u0000')) {
      return null;
    }
    path = value;
  }
  final uri = Directory(path).absolute.uri.normalizePath();
  if (uri.path == Directory(home).absolute.uri.normalizePath().path) {
    return null;
  }
  final normalized = Directory.fromUri(uri).path;
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

String fileName(String path) => path.split('/').where((p) => p.isNotEmpty).last;
bool validFileName(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.contains('\u0000');

/// Label shown below a desktop icon.
///
/// Windows hides the `.desktop` implementation suffix, so a shortcut without a
/// usable `Name` shows `firefox`, never `firefox.desktop`. Ordinary files keep
/// their real file name, which the file manager also shows.
String displayName(String path, DesktopEntry? entry, String locale) {
  final name = entry?.name('', locale).trim() ?? '';
  if (name.isNotEmpty) return name;
  final file = fileName(path);
  if (!file.toLowerCase().endsWith('.desktop')) return file;
  final stem = file.substring(0, file.length - '.desktop'.length).trim();
  return stem.isEmpty ? file : stem;
}

class DesktopEntry {
  const DesktopEntry(this.fields);
  final Map<String, String> fields;
  static DesktopEntry parse(String text) {
    if (text.contains('\u0000')) throw const FormatException('入口含有 NUL 字符');
    final fields = <String, String>{};
    var inside = false;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().startsWith('[')) {
        inside = line.trim() == '[Desktop Entry]';
        continue;
      }
      if (!inside || line.startsWith('#')) continue;
      final split = line.indexOf('=');
      if (split > 0) {
        fields[line.substring(0, split).trim()] = line.substring(split + 1);
      }
    }
    return DesktopEntry(fields);
  }

  String name(String fallback, String locale) {
    final language = locale.split('.').first.split('@').first;
    return fields['Name[$language]'] ??
        fields['Name[${language.split('_').first}]'] ??
        fields['Name'] ??
        fallback;
  }

  bool get application =>
      fields['Type'] == 'Application' &&
      ((fields['Exec']?.isNotEmpty ?? false) ||
          fields['DBusActivatable'] == 'true');
}

class DesktopItem {
  const DesktopItem({
    required this.path,
    required this.name,
    required this.directory,
    this.entry,
    this.problem,
  });
  final String path, name;
  final bool directory;
  final DesktopEntry? entry;
  final String? problem;
  String get key => fileName(path);
  bool get shortcut => !directory && path.endsWith('.desktop');
}

/// Reuse unchanged metadata after a real rescan; never skip file validation.
/// This keeps icon/text subtrees alive when an unrelated desktop file changes.
List<DesktopItem> reuseDesktopItems(
  List<DesktopItem> previous,
  List<DesktopItem> next,
) {
  final byPath = {for (final item in previous) item.path: item};
  final result = <DesktopItem>[];
  for (final item in next) {
    final old = byPath[item.path];
    final oldFields = old?.entry?.fields;
    final fields = item.entry?.fields;
    final sameFields = oldFields == null
        ? fields == null
        : fields != null &&
              oldFields.length == fields.length &&
              oldFields.entries.every((e) => fields[e.key] == e.value);
    result.add(
      old != null &&
              old.name == item.name &&
              old.directory == item.directory &&
              old.problem == item.problem &&
              sameFields
          ? old
          : item,
    );
  }
  if (result.length == previous.length) {
    var sameOrder = true;
    for (var i = 0; i < result.length; i++) {
      if (!identical(result[i], previous[i])) {
        sameOrder = false;
        break;
      }
    }
    if (sameOrder) return previous;
  }
  return result;
}

/// System operations are centralized, never invoke a shell, and only run on explicit UI actions.
abstract interface class FileActions {
  Future<void> open(DesktopItem item);
  Future<void> trash(DesktopItem item);
  Future<void> rename(String source, String target);
}

class GioFileActions implements FileActions {
  const GioFileActions();
  Future<void> _run(List<String> args) async {
    final result = await Process.run('gio', args, runInShell: false);
    if (result.exitCode != 0) {
      throw FileSystemException(
        '${result.stderr}'.trim().isEmpty
            ? 'GIO 操作失败（${result.exitCode}）'
            : '${result.stderr}'.trim(),
      );
    }
  }

  @override
  Future<void> open(DesktopItem item) =>
      _run([item.shortcut ? 'launch' : 'open', item.path]);
  @override
  Future<void> trash(DesktopItem item) => _run(['trash', '--', item.path]);
  @override
  Future<void> rename(String source, String target) async =>
      renameNoReplace(source, target);
}

class GridSlot {
  const GridSlot(this.column, this.row);
  final int column, row;
  @override
  bool operator ==(Object other) =>
      other is GridSlot && column == other.column && row == other.row;
  @override
  int get hashCode => Object.hash(column, row);
  List<int> toJson() => [column, row];
}

/// Collision-free column-major layout, preserving positions where they still fit.
Map<String, GridSlot> arrange(
  List<String> keys,
  Map<String, GridSlot> saved,
  int columns,
  int rows,
) {
  final result = <String, GridSlot>{};
  final used = <GridSlot>{};
  columns = math.max(1, columns);
  rows = math.max(1, rows);
  for (final key in keys) {
    final slot = saved[key];
    if (slot != null &&
        slot.column >= 0 &&
        slot.column < columns &&
        slot.row >= 0 &&
        slot.row < rows &&
        used.add(slot)) {
      result[key] = slot;
    }
  }
  var index = 0;
  for (final key in keys) {
    if (result.containsKey(key)) continue;
    while (used.contains(GridSlot(index ~/ rows, index % rows))) {
      index++;
    }
    final slot = GridSlot(index ~/ rows, index % rows);
    result[key] = slot;
    used.add(slot);
  }
  return result;
}

/// Serializes scans while merging requests made during one scan into the next.
/// Each caller waits for the scan that includes its request, rather than an
/// earlier scan that may already have read the directory before that request.
class DesktopRefreshQueue {
  DesktopRefreshQueue(this.scan);

  final Future<void> Function() scan;
  List<Completer<void>> _pending = [];
  bool _inFlight = false;
  bool _disposed = false;

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final completion = Completer<void>();
    _pending.add(completion);
    if (!_inFlight) {
      _inFlight = true;
      unawaited(_drain());
    }
    return completion.future;
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && _pending.isNotEmpty) {
        final covered = _pending;
        _pending = [];
        try {
          await scan();
          for (final completion in covered) {
            completion.complete();
          }
        } on Object catch (error, stack) {
          // A failed scan must neither poison the queue nor discard requests
          // that arrived while it was running.
          for (final completion in covered) {
            completion.completeError(error, stack);
          }
        }
      }
    } finally {
      _inFlight = false;
    }
  }

  void dispose() {
    _disposed = true;
    for (final completion in _pending) {
      completion.complete();
    }
    _pending.clear();
  }
}

class DesktopStore {
  DesktopStore({
    Map<String, String>? environment,
    this.actions = const GioFileActions(),
    this.onChanged,
  }) : environment = Map.unmodifiable(environment ?? Platform.environment);
  final Map<String, String> environment;
  final FileActions actions;
  final void Function()? onChanged;
  List<DesktopItem> items = [];
  String? directory, error;
  bool loading = true, disposed = false;
  int _generation = 0;
  Timer? _debounce;
  final List<StreamSubscription<FileSystemEvent>> _watches = [];
  Map<String, GridSlot> positions = {};
  bool showHidden = false;
  double iconSize = 48;
  Future<void> _writes = Future.value();
  late final _refreshes = DesktopRefreshQueue(_refresh);
  String get home => environment['HOME'] ?? '';
  String get configRoot => environment['XDG_CONFIG_HOME'] ?? '$home/.config';
  File get config => File('$configRoot/desk_canvas/layout.json');
  String? get environmentError {
    if (!home.startsWith('/') || home.contains('\u0000')) {
      return 'HOME 必须为有效绝对路径';
    }
    if (!configRoot.startsWith('/') || configRoot.contains('\u0000')) {
      return 'XDG_CONFIG_HOME 必须为有效绝对路径';
    }
    return null;
  }

  Future<void> start() async {
    if (disposed) return;
    if (environmentError case final problem?) {
      error = problem;
      loading = false;
      onChanged?.call();
      return;
    }
    try {
      if (await config.exists()) {
        final value = jsonDecode(await readBounded(config, 1024 * 1024));
        if (value is Map && value['version'] == 1) {
          showHidden = value['showHidden'] == true;
          final size = value['iconSize'];
          if (size is num) iconSize = size.toDouble().clamp(32, 80);
          if (value['positions'] is Map) {
            for (final entry in (value['positions'] as Map).entries) {
              final p = entry.value;
              if (entry.key is String &&
                  p is List &&
                  p.length == 2 &&
                  p[0] is int &&
                  p[1] is int) {
                positions[entry.key as String] = GridSlot(p[0], p[1]);
              }
            }
          }
        }
      }
    } on Object {
      /* Invalid layout never hides real desktop content. */
    }
    await refresh();
  }

  void scheduleRefresh() {
    if (disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), refresh);
  }

  Future<void> refresh() {
    if (disposed) return Future.value();
    if (environmentError case final problem?) {
      error = problem;
      loading = false;
      onChanged?.call();
      return Future.value();
    }
    return _refreshes.refresh();
  }

  Future<void> _refresh() async {
    if (disposed) return;
    final generation = ++_generation;
    final previousWatches = List.of(_watches);
    _watches.clear();
    for (final watch in previousWatches) {
      await watch.cancel();
    }
    if (disposed || generation != _generation) return;
    String? nextDirectory;
    // Keep configuration recovery alive even when its content is unreadable.
    var configWatch = Directory(configRoot);
    while (!await configWatch.exists() &&
        configWatch.parent.path != configWatch.path) {
      configWatch = configWatch.parent;
    }
    if (disposed || generation != _generation) return;
    try {
      _watches.add(
        configWatch.watch().listen(
          (event) {
            if (configWatch.path == configRoot &&
                fileName(event.path) != 'user-dirs.dirs') {
              return;
            }
            if (configWatch.path != configRoot &&
                event.path != configRoot &&
                !configRoot.startsWith('${event.path}/')) {
              return;
            }
            scheduleRefresh();
          },
          onError: (Object e) {
            if (!disposed) {
              error = '配置目录监听不可用：$e';
              onChanged?.call();
            }
          },
        ),
      );
    } on FileSystemException {
      /* A manual refresh remains available. */
    }
    try {
      final userDirs = File('$configRoot/user-dirs.dirs');
      if (await userDirs.exists()) {
        nextDirectory = desktopDirectory(
          await readBounded(userDirs, 65536),
          home,
        );
      } else if (home.isNotEmpty) {
        nextDirectory = '$home/Desktop';
      }
      if (disposed || generation != _generation) return;
      directory = nextDirectory;
      // Watch before listing so a creation during the initial scan is not lost.
      final watchPaths = <String>{};
      if (nextDirectory != null) {
        var parent = Directory(nextDirectory).parent;
        while (!await parent.exists() && parent.parent.path != parent.path) {
          parent = parent.parent;
        }
        watchPaths.add(parent.path);
        if (await Directory(nextDirectory).exists()) {
          watchPaths.add(nextDirectory);
        }
      }
      if (disposed || generation != _generation) return;
      for (final path in watchPaths) {
        try {
          _watches.add(
            Directory(path).watch().listen(
              (event) {
                if (path != nextDirectory &&
                    event.path != nextDirectory &&
                    !(nextDirectory?.startsWith('${event.path}/') ?? false)) {
                  return;
                }
                scheduleRefresh();
              },
              onError: (Object e) {
                if (!disposed) {
                  error = '目录监听不可用：$e（可右键刷新）';
                  onChanged?.call();
                }
              },
            ),
          );
        } on FileSystemException {
          /* Listing below provides the actionable error. */
        }
      }
      if (nextDirectory == null) {
        throw const FileSystemException('未配置有效的 XDG 桌面目录，请在系统用户目录配置中设置桌面。');
      }
      final next = <DesktopItem>[];
      final locale =
          environment['LC_ALL'] ??
          environment['LC_MESSAGES'] ??
          environment['LANG'] ??
          '';
      await for (final entity in Directory(
        nextDirectory,
      ).list(followLinks: false)) {
        final key = fileName(entity.path);
        if (!showHidden && key.startsWith('.')) continue;
        if (next.length >= 10000) {
          throw const FileSystemException('桌面项目超过 10000 个，请在文件管理器中整理。');
        }
        final type = await FileSystemEntity.type(entity.path);
        DesktopEntry? entry;
        String? problem;
        if (type != FileSystemEntityType.directory &&
            key.endsWith('.desktop')) {
          try {
            final file = File(entity.path);
            entry = DesktopEntry.parse(await readBounded(file, 262144));
            if (!entry.application) problem = '不是有效的应用快捷方式';
          } on Object {
            problem = '无法读取快捷方式';
          }
        }
        if (type == FileSystemEntityType.notFound) problem = '链接目标不存在';
        next.add(
          DesktopItem(
            path: entity.path,
            name: displayName(entity.path, entry, locale),
            directory: type == FileSystemEntityType.directory,
            entry: entry,
            problem: problem,
          ),
        );
      }
      next.sort((a, b) {
        if (a.directory != b.directory) return a.directory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (disposed || generation != _generation) return;
      items = reuseDesktopItems(items, next);
      error = null;
    } on Object catch (e) {
      if (disposed || generation != _generation) return;
      items = [];
      error = '$e';
    }
    loading = false;
    if (!disposed && generation == _generation) onChanged?.call();
  }

  Future<void> save() {
    if (environmentError case final problem?) {
      return Future.error(FileSystemException(problem));
    }
    final payload = jsonEncode({
      'version': 1,
      'iconSize': iconSize,
      'showHidden': showHidden,
      'positions': positions.map((key, value) => MapEntry(key, value.toJson())),
    });
    final target = config;
    return _writes = _writes.catchError((Object _) {}).then((_) async {
      await target.parent.create(recursive: true);
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(target.path);
    });
  }

  Future<void> validateItem(DesktopItem item) async {
    if (disposed ||
        directory == null ||
        Directory(item.path).parent.path != directory ||
        !items.any((i) => i.path == item.path)) {
      throw const FileSystemException('桌面项目已经改变，请刷新后重试');
    }
    if (await FileSystemEntity.type(item.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw const FileSystemException('项目已经移除');
    }
  }

  Future<void> createFolder(String name) async {
    if (!validFileName(name) || directory == null) {
      throw const FileSystemException('文件夹名称无效');
    }
    final path = '$directory/$name';
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('该名称已经存在');
    }
    await Directory(path).create();
    await refresh();
  }

  Future<void> rename(DesktopItem item, String name) async {
    if (!validFileName(name) ||
        directory == null ||
        !items.any((i) => i.path == item.path)) {
      throw const FileSystemException('文件名称无效或项目已经移除');
    }
    if (name == item.key) return;
    final target = '$directory/$name';
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('该名称已经存在');
    }
    if (Directory(item.path).parent.path != directory) {
      throw const FileSystemException('桌面目录已经改变，请刷新后重试');
    }
    await actions.rename(item.path, target);
    final slot = positions.remove(item.key);
    if (slot != null) positions[name] = slot;
    await save();
    await refresh();
  }

  Future<void> dispose() async {
    disposed = true;
    _refreshes.dispose();
    _generation++;
    _debounce?.cancel();
    final previousWatches = List.of(_watches);
    _watches.clear();
    for (final watch in previousWatches) {
      await watch.cancel();
    }
  }
}

/// Read at most limit + 1 bytes even if another process grows the file concurrently.
Future<String> readBounded(File file, int limit) async {
  final handle = await file.open();
  try {
    final bytes = await handle.read(limit + 1);
    if (bytes.length > limit) throw const FormatException('文件超过读取上限');
    return utf8.decode(bytes);
  } finally {
    await handle.close();
  }
}
