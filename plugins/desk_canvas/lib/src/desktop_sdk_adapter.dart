// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:isolate';

import 'package:denial_flutter_sdk/applications.dart';

import 'desktop_store.dart';

/// Theme icon filesystem traversal is performed off the UI isolate and cached.
Future<Map<String, String?>> resolveDesktopIcons(List<String> icons) {
  final environment = Platform.environment;
  return Isolate.run(() {
    final repository = DesktopAppsRepository(
      paths: RuntimePaths(environment: environment),
    );
    return {for (final icon in icons) icon: repository.resolveIconPath(icon)};
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
