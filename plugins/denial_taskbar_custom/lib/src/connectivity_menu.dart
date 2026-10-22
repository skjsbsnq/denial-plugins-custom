import 'dart:async';

import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectivityMenuKind { wifi, bluetooth }

class ConnectivityMenu extends StatelessWidget {
  const ConnectivityMenu({required this.kind, required this.onBack, super.key});
  final ConnectivityMenuKind kind;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => kind == ConnectivityMenuKind.wifi
      ? _WifiMenu(onBack: onBack)
      : _BluetoothMenu(onBack: onBack);
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading({
    required this.title,
    required this.onBack,
    required this.onRefresh,
    required this.busy,
  });
  final String title;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Row(
      children: [
        IconButton(
          tooltip: zh ? '返回控制中心' : 'Back to control center',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(child: Text(title, style: context.shellTheme.text.cardTitle)),
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        IconButton(
          tooltip: zh ? '刷新' : 'Refresh',
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _WifiMenu extends ConsumerStatefulWidget {
  const _WifiMenu({required this.onBack});
  final VoidCallback onBack;
  @override
  ConsumerState<_WifiMenu> createState() => _WifiMenuState();
}

class _WifiMenuState extends ConsumerState<_WifiMenu> {
  final _password = TextEditingController();
  String? _networkIdentity;
  bool _showPassword = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect(WifiNetwork network) async {
    final controller = ref.read(networkConnectivityProvider.notifier);
    await controller.connect(network, password: _password.text);
    if (mounted && ref.read(networkConnectivityProvider).error == null) {
      setState(() => _networkIdentity = null);
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String text(String cn, String en) => zh ? cn : en;
    final state = ref.watch(networkConnectivityProvider);
    final controller = ref.read(networkConnectivityProvider.notifier);
    final snapshot = state.snapshot;
    final hardware =
        snapshot.serviceAvailable &&
        snapshot.wifiDeviceAvailable &&
        snapshot.wirelessHardwareEnabled;
    final canControl = snapshot.controlPermission != NetworkPermission.denied;
    final networks = [...snapshot.networks]
      ..sort((a, b) {
        if (a.connected != b.connected) return a.connected ? -1 : 1;
        if (a.saved != b.saved) return a.saved ? -1 : 1;
        return b.strength.compareTo(a.strength);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MenuHeading(
          title: 'Wi-Fi',
          onBack: widget.onBack,
          busy: state.initializing || state.scanning,
          onRefresh: hardware && snapshot.wirelessEnabled && canControl
              ? () => unawaited(controller.scan())
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wi-Fi'),
          value: snapshot.wirelessEnabled,
          onChanged:
              hardware &&
                  !state.radioChanging &&
                  snapshot.radioPermission != NetworkPermission.denied
              ? (value) => unawaited(controller.setWirelessEnabled(value))
              : null,
        ),
        if (state.error != null) _Notice(state.error!, error: true),
        if (!hardware)
          _Notice(text('Wi-Fi 设备不可用', 'Wi-Fi is unavailable'))
        else if (!snapshot.wirelessEnabled)
          _Notice(text('打开 Wi-Fi 后查看网络', 'Turn on Wi-Fi to view networks'))
        else if (networks.isEmpty)
          _Notice(
            text('未找到网络，点击刷新重新扫描', 'No networks found. Refresh to scan again.'),
          ),
        for (final network
            in (hardware && snapshot.wirelessEnabled
                ? networks
                : <WifiNetwork>[])) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              network.security == WifiSecurity.open
                  ? Icons.wifi_rounded
                  : Icons.wifi_lock_rounded,
            ),
            title: Text(
              network.ssid,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              network.connected
                  ? text('已连接', 'Connected')
                  : !network.supported || !network.connectable
                  ? text('此网络暂不支持直接连接', 'Cannot connect to this network here')
                  : network.saved
                  ? text('已保存', 'Saved')
                  : '${network.strength} % · ${network.security.label}',
            ),
            trailing: state.busyNetworks.contains(network.identity)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    network.connected
                        ? Icons.check_rounded
                        : Icons.chevron_right_rounded,
                  ),
            enabled:
                canControl &&
                !state.busyNetworks.contains(network.identity) &&
                (network.connected ||
                    (network.connectable &&
                        (network.saved ||
                            snapshot.modifyPermission !=
                                NetworkPermission.denied))),
            onTap: network.connected
                ? null
                : () {
                    if (!network.saved && network.security.requiresPassword) {
                      _password.clear();
                      setState(() {
                        _networkIdentity = network.identity;
                        _showPassword = false;
                      });
                    } else {
                      setState(() => _networkIdentity = null);
                      _password.clear();
                      unawaited(controller.connect(network));
                    }
                  },
          ),
          if (_networkIdentity == network.identity && !network.connected)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: text('网络密码', 'Network password'),
                      suffixIcon: IconButton(
                        tooltip: text('显示或隐藏密码', 'Show or hide password'),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_password.text.isNotEmpty &&
                          !state.busyNetworks.contains(network.identity)) {
                        unawaited(_connect(network));
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() => _networkIdentity = null);
                          _password.clear();
                        },
                        child: Text(text('取消', 'Cancel')),
                      ),
                      FilledButton(
                        onPressed:
                            _password.text.isEmpty ||
                                state.busyNetworks.contains(network.identity)
                            ? null
                            : () => unawaited(_connect(network)),
                        child: Text(text('连接', 'Connect')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (network.connected)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed:
                    state.busyNetworks.contains(network.identity) || !canControl
                    ? null
                    : () => unawaited(controller.disconnect(network)),
                child: Text(text('断开连接', 'Disconnect')),
              ),
            ),
        ],
      ],
    );
  }
}

class _BluetoothMenu extends ConsumerWidget {
  const _BluetoothMenu({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String text(String cn, String en) => zh ? cn : en;
    final state = ref.watch(bluetoothProvider);
    final controller = ref.read(bluetoothProvider.notifier);
    final devices = [...state.devices]
      ..sort((a, b) {
        if (a.connected != b.connected) return a.connected ? -1 : 1;
        if (a.paired != b.paired) return a.paired ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MenuHeading(
          title: text('蓝牙', 'Bluetooth'),
          busy: state.initializing || state.scanning,
          onBack: () {
            if (state.pairingRequest != null) {
              controller.respondToPairing(accepted: false);
            }
            onBack();
          },
          onRefresh: state.available && state.powered
              ? () => unawaited(controller.scan())
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(text('蓝牙', 'Bluetooth')),
          value: state.powered,
          onChanged:
              state.available && !state.initializing && !state.powerChanging
              ? (_) => unawaited(controller.togglePower())
              : null,
        ),
        if (state.error != null) _Notice(state.error!, error: true),
        if (!state.available)
          _Notice(text('蓝牙设备不可用', 'Bluetooth is unavailable'))
        else if (!state.powered)
          _Notice(text('打开蓝牙后查看设备', 'Turn on Bluetooth to view devices'))
        else if (devices.isEmpty)
          _Notice(
            text(
              '未找到设备，点击刷新开始搜索',
              'No devices found. Refresh to start discovery.',
            ),
          ),
        if (state.pairingRequest case final request?)
          _PairingPrompt(key: ValueKey(request.id), request: request),
        for (final device in devices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              device.connected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
            ),
            title: Text(
              device.name.isEmpty ? device.address : device.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              device.blocked
                  ? text('设备已被阻止', 'Device blocked')
                  : device.connected
                  ? text('已连接 · 点击断开', 'Connected · Select to disconnect')
                  : device.paired
                  ? text('已配对 · 点击连接', 'Paired · Select to connect')
                  : text('点击配对并连接', 'Select to pair and connect'),
            ),
            trailing: state.busyDevices.contains(device.objectPath)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    device.connected
                        ? Icons.check_rounded
                        : Icons.chevron_right_rounded,
                  ),
            enabled:
                state.available &&
                state.powered &&
                !device.blocked &&
                !state.busyDevices.contains(device.objectPath) &&
                state.pairingRequest == null,
            onTap: () => unawaited(controller.toggleConnection(device)),
          ),
      ],
    );
  }
}

class _PairingPrompt extends ConsumerStatefulWidget {
  const _PairingPrompt({required this.request, super.key});
  final BluetoothPairingRequest request;
  @override
  ConsumerState<_PairingPrompt> createState() => _PairingPromptState();
}

class _PairingPromptState extends ConsumerState<_PairingPrompt> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _respond(bool accepted) {
    if (ref.read(bluetoothProvider).pairingRequest?.id != widget.request.id) {
      return;
    }
    ref
        .read(bluetoothProvider.notifier)
        .respondToPairing(
          accepted: accepted,
          response: widget.request.kind.needsTextInput ? _input.text : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String text(String cn, String en) => zh ? cn : en;
    final request = widget.request;
    final passkey = request.kind == BluetoothPairingRequestKind.passkey;
    final valid =
        !request.kind.needsTextInput ||
        (passkey
            ? RegExp(r'^\d{1,6}$').hasMatch(_input.text)
            : _input.text.isNotEmpty && _input.text.length <= 16);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.shellTheme.accentPalette.mutedContainer,
        borderRadius: context.shellTheme.borderRadius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${text('蓝牙配对', 'Bluetooth pairing')} · ${request.deviceName}'),
          if (request.passkey != null)
            Text(
              request.passkey.toString().padLeft(6, '0'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          if (request.pinCode != null)
            Text(
              request.pinCode!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          if (request.kind.needsTextInput)
            TextField(
              controller: _input,
              keyboardType: passkey ? TextInputType.number : TextInputType.text,
              inputFormatters: [
                if (passkey) FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(passkey ? 6 : 16),
              ],
              decoration: InputDecoration(
                labelText: passkey ? text('配对码', 'Passkey') : 'PIN',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (valid) _respond(true);
              },
            ),
          if (request.kind.informational)
            Text(text('请在另一台设备上输入此配对码', 'Enter this code on the other device'))
          else if (!request.kind.needsTextInput)
            Text(
              text(
                '确认设备和配对码后允许配对',
                'Check the device and code before accepting',
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _respond(false),
                child: Text(text('取消', 'Cancel')),
              ),
              if (!request.kind.informational)
                FilledButton(
                  onPressed: valid ? () => _respond(true) : null,
                  child: Text(text('确认配对', 'Accept pairing')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      message,
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.error
            : context.shellColors.textSecondary,
      ),
    ),
  );
}
