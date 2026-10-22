import 'dart:convert';
import 'dart:io';

class ControlCenterProfile {
  const ControlCenterProfile({required this.name, this.avatarPath});
  final String name;
  final String? avatarPath;
}

/// Read-only adapter for the reference desktop's schema-1 profile document.
/// There is currently no profile capability in ShellServices. Never write to
/// another plugin's preferences or accept paths from the profile document.
Future<ControlCenterProfile> readControlCenterProfile(
  Map<String, String> environment,
) async {
  final account =
      [environment['USER'], environment['LOGNAME']]
          .whereType<String>()
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .firstOrNull ??
      '';
  final fallback = ControlCenterProfile(name: account);
  final config = environment['XDG_CONFIG_HOME']?.trim();
  final home = environment['HOME']?.trim();
  final root = config != null && config.startsWith('/')
      ? config
      : home != null && home.startsWith('/')
      ? '$home/.config'
      : null;
  if (root == null) return fallback;
  final directory = '$root/denial/plugins/denial_desktop/profile';
  final file = File('$directory/profile.json');
  try {
    if (!await file.exists() || await file.length() > 65536) return fallback;
    final content = await file.readAsString();
    if (utf8.encode(content).length > 65536) return fallback;
    final value = jsonDecode(content);
    if (value is! Map || value['schema'] != 1) return fallback;
    final name = value['displayName'];
    final avatar = value['avatar'];
    final validName =
        name is String &&
        name.trim().isNotEmpty &&
        name.runes.length <= 200 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name);
    final validAvatar =
        avatar is String &&
        RegExp(r'^avatar-[0-9]+-[0-9]+\.png$').hasMatch(avatar);
    return ControlCenterProfile(
      name: validName ? name.trim() : account,
      avatarPath: validAvatar ? '$directory/$avatar' : null,
    );
  } on FileSystemException {
    return fallback;
  } on FormatException {
    return fallback;
  }
}
