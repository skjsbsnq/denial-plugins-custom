import 'dart:convert';
import 'dart:io';

class NetworkInterfaceDetails {
  const NetworkInterfaceDetails({
    required this.name,
    required this.state,
    required this.mac,
    required this.megabits,
    required this.addresses,
  });
  final String name;
  final String? state;
  final String? mac;
  final int? megabits;
  final List<String> addresses;
}

Future<String?> _readAttribute(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final bytes = await file.read(129);
    return bytes.length > 128 ? null : utf8.decode(bytes).trim();
  } on FileSystemException catch (error) {
    if ([2, 19, 22, 95].contains(error.osError?.errorCode)) return null;
    rethrow;
  } on FormatException {
    return null;
  } finally {
    await file?.close();
  }
}

Future<List<NetworkInterfaceDetails>> readNetworkInterfaceDetails(
  Iterable<String> names, {
  String root = '/sys/class/net',
  Map<String, List<String>>? localAddresses,
}) async {
  final addresses =
      localAddresses ??
      {
        for (final interface in await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: false,
        ))
          interface.name: interface.addresses.map((a) => a.address).toList(),
      };
  final result = <NetworkInterfaceDetails>[];
  for (final name in names.take(64)) {
    if (name == '.' ||
        name == '..' ||
        !RegExp(r'^[a-zA-Z0-9_.:+-]{1,64}$').hasMatch(name)) {
      continue;
    }
    final state = await _readAttribute('$root/$name/operstate');
    final mac = await _readAttribute('$root/$name/address');
    final speed = int.tryParse(await _readAttribute('$root/$name/speed') ?? '');
    result.add(
      NetworkInterfaceDetails(
        name: name,
        state:
            const [
              'up',
              'down',
              'dormant',
              'unknown',
              'lowerlayerdown',
              'notpresent',
              'testing',
            ].contains(state)
            ? state
            : null,
        mac:
            mac != null &&
                mac != '00:00:00:00:00:00' &&
                RegExp(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$').hasMatch(mac)
            ? mac
            : null,
        megabits: speed != null && speed > 0 && speed <= 10000000
            ? speed
            : null,
        addresses: List.unmodifiable(
          (addresses[name] ?? []).where(
            (a) => InternetAddress.tryParse(a) != null,
          ),
        ),
      ),
    );
  }
  return List.unmodifiable(result);
}
