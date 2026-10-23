// SPDX-License-Identifier: GPL-3.0-or-later
@Plugin()
library;

import 'package:denial_flutter_sdk/actions.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'src/app_shelf_view.dart';

@Provides(ShellLauncher)
final class AppShelfPlugin implements ShellLauncher {
  const AppShelfPlugin();

  @override
  Widget build(BuildContext context, {required LauncherContext launcher}) =>
      AppShelfView(launcher: launcher);
}

@Provides(ShellAction)
final class OpenAppShelfAction implements ShellAction {
  const OpenAppShelfAction();

  @override
  String get id => 'app_shelf.openApplications';

  @override
  String get provider => 'App Shelf';

  @override
  String label(BuildContext context) => 'App Shelf';

  @override
  String description(BuildContext context) => '';

  @override
  void invoke(ShellActionContext context) => context.services.toggleLauncher();
}
