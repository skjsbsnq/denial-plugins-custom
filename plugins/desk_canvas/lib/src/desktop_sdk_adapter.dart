// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:isolate';

import 'package:denial_flutter_sdk/applications.dart';

import 'desktop_store.dart';

/// Icon names resolve to the same path for the life of the process, so the
/// result is kept here instead of being discarded with each refresh.
final _iconPaths = <String, String?>{};
Future<void> _queuedIcons = Future.value();

/// Theme icon filesystem traversal is performed off the UI isolate, one batch
/// at a time, and cached. Rarely changing icons no longer respawn an isolate —
/// with a cold repository that re-walked every icon theme directory — after
/// each desktop event.
Future<Map<String, String?>> resolveDesktopIcons(List<String> icons) {
  final known = <String, String?>{
    for (final icon in icons)
      if (_iconPaths.containsKey(icon)) icon: _iconPaths[icon],
  };
  final missing = icons.where((icon) => !_iconPaths.containsKey(icon)).toList();
  if (missing.isEmpty) return Future.value(known);
  final batch = _queuedIcons.then((_) async {
    final environment = Platform.environment;
    final resolved = await Isolate.run(() {
      final repository = DesktopAppsRepository(
        paths: RuntimePaths(environment: environment),
      );
      return {
        for (final icon in missing) icon: repository.resolveIconPath(icon),
      };
    });
    _iconPaths.addAll(resolved);
    return resolved;
  });
  _queuedIcons = batch.then<void>((_) {}, onError: (Object _) {});
  return batch.then((resolved) => {...known, ...resolved});
}

/// Reads the installed application catalog once per shortcut launch.
///
/// This deliberately avoids the home grid controller: that controller keeps
/// application-directory watchers and a periodic rescan alive for the rest of
/// the session, which a desktop-only plugin should not pay for.
Future<List<DesktopApp>> loadInstalledApplications() {
  final environment = Platform.environment;
  return Isolate.run(() {
    final repository = DesktopAppsRepository(
      paths: RuntimePaths(environment: environment),
    );
    return repository.loadApplications();
  });
}

/// Only identical installed entries may bypass the external-shortcut confirmation.
Future<DesktopApp?> installedEntry(
  DesktopItem item,
  Iterable<DesktopApp> apps,
) async {
  if (!item.shortcut) return null;
  final desktop = await readBounded(File(item.path), 262144);
  for (final app in apps) {
    if (fileName(app.desktopPath) != item.key) continue;
    try {
      if (await readBounded(File(app.desktopPath), 262144) == desktop) {
        return app;
      }
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    }
  }
  return null;
}
