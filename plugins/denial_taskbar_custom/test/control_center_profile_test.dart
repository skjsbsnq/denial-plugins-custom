import 'dart:convert';
import 'dart:io';

import 'package:denial_taskbar_custom/src/control_center_profile.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('control-center-profile-');
  try {
    final environment = {'XDG_CONFIG_HOME': root.path, 'USER': 'account'};
    check(
      (await readControlCenterProfile(environment)).name == 'account',
      'Missing profiles must fall back to the account name.',
    );
    final directory = await Directory(
      '${root.path}/denial/plugins/denial_desktop/profile',
    ).create(recursive: true);
    final file = File('${directory.path}/profile.json');
    await file.writeAsString(
      jsonEncode({
        'schema': 1,
        'displayName': ' My name ',
        'avatar': 'avatar-123-456.png',
      }),
    );
    final valid = await readControlCenterProfile(environment);
    check(
      valid.name == 'My name' &&
          valid.avatarPath == '${directory.path}/avatar-123-456.png',
      'The reference desktop profile must supply the displayed name and avatar.',
    );
    final before = await file.readAsString();
    await readControlCenterProfile(environment);
    check(
      await file.readAsString() == before,
      'Reading must never modify desktop preferences.',
    );

    await file.writeAsString(
      jsonEncode({
        'schema': 1,
        'displayName': 'bad\nname',
        'avatar': '../../secret.png',
      }),
    );
    final unsafe = await readControlCenterProfile(environment);
    check(
      unsafe.name == 'account' && unsafe.avatarPath == null,
      'Control characters and paths outside the avatar naming contract must be rejected.',
    );
    for (final content in [
      '{invalid',
      '{"schema":2,"displayName":"other"}',
      'x' * 65537,
    ]) {
      await file.writeAsString(content);
      check(
        (await readControlCenterProfile(environment)).name == 'account',
        'Invalid, unsupported or oversized profiles must not break the panel.',
      );
    }
    check(
      (await readControlCenterProfile({'LOGNAME': 'fallback'})).name ==
          'fallback',
      'Missing config roots should not prevent the LOGNAME fallback.',
    );
  } finally {
    await root.delete(recursive: true);
  }
  stdout.writeln(
    'Control center read-only profile and fallback checks passed.',
  );
}
