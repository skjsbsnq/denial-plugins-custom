// Layout inspired by Stats (MIT), Copyright (c) 2019 Serhiy Mytrovtsiy.
// See third_party/stats-LICENSE. No process monitoring is performed.
import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_speed.dart';
import 'network_telemetry_state.dart';
import 'stats_panel.dart';
import 'network_detail_row.dart';

class NetworkPanel extends ConsumerWidget {
  const NetworkPanel({required this.onClose, super.key});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(networkTelemetryProvider).value;
    final network = ref.watch(networkConnectivityProvider);
    final interfaces = ref.watch(networkInterfaceDetailsProvider);
    final snapshot = network.snapshot;
    final wifi = snapshot.connectedNetwork;
    final history = telemetry?.history ?? const <NetworkHistoryPoint>[];
    final colors = Theme.of(context).colorScheme;
    final downColor = context.shellTheme.accent;
    final upColor = Color.lerp(downColor, colors.onSurface, .55)!;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String cn, String en) => zh ? cn : en;
    final status = network.initializing
        ? t('正在读取…', 'Loading…')
        : switch (snapshot.status) {
            NetworkConnectivityStatus.unavailable => t('不可用', 'Unavailable'),
            NetworkConnectivityStatus.disabled => t('已禁用', 'Disabled'),
            NetworkConnectivityStatus.disconnected => t('未连接', 'Disconnected'),
            NetworkConnectivityStatus.connecting => t('连接中', 'Connecting'),
            NetworkConnectivityStatus.local => t('仅本地网络', 'Local network only'),
            NetworkConnectivityStatus.limited => t('连接受限', 'Limited'),
            NetworkConnectivityStatus.captivePortal => t(
              '需要网页登录',
              'Sign-in required',
            ),
            NetworkConnectivityStatus.online => t('已联网', 'Online'),
          };
    double peak = 0;
    for (final point in history) {
      peak = math.max(
        peak,
        math.max(point.speed?.upload ?? 0, point.speed?.download ?? 0),
      );
    }
    Widget rate(String label, double? value, Color color, IconData icon) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatNetworkSpeed(value),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        );
    final ready = telemetry != null && telemetry.error == null;
    return StatsPanel(
      title: t('网络', 'Network'),
      icon: Icons.network_check_rounded,
      onClose: onClose,
      onRefresh: () {
        ref.invalidate(networkInterfaceDetailsProvider);
        unawaited(ref.read(networkConnectivityProvider.notifier).refresh());
      },
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            rate(
              t('下载', 'Download'),
              telemetry?.speed?.download,
              downColor,
              Icons.south_rounded,
            ),
            const SizedBox(width: 12),
            rate(
              t('上传', 'Upload'),
              telemetry?.speed?.upload,
              upColor,
              Icons.north_rounded,
            ),
          ],
        ),
        const SizedBox(height: 10),
        StatsSection(t('流量历史', 'Usage history')),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: .04),
            borderRadius: context.shellTheme.borderRadius(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${t('峰值', 'Peak')} ${history.any((p) => p.speed != null) ? formatNetworkSpeed(peak) : '—'}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 6),
              Semantics(
                label: t(
                  '上半部为下载，下半部为上传；显示最近的流量历史',
                  'Recent traffic: download above, upload below',
                ),
                child: SizedBox(
                  height: 104,
                  child: CustomPaint(
                    painter: _TrafficChart(
                      history,
                      peak,
                      downColor,
                      upColor,
                      colors.outlineVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        StatsSection(t('联网历史', 'Connectivity history')),
        LayoutBuilder(
          builder: (context, constraints) {
            final cells = List<NetworkHistoryPoint?>.filled(60, null);
            for (var i = 0; i < history.length; i++) {
              cells[60 - history.length + i] = history[i];
            }
            final width = math.max(1.0, (constraints.maxWidth - 14 * 3) / 15);
            return Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final cell in cells)
                  SizedBox(
                    width: width,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cell?.online == null
                            ? colors.onSurface.withValues(alpha: .06)
                            : cell!.online!
                            ? downColor
                            : colors.error.withValues(alpha: .6),
                        borderRadius: context.shellTheme.borderRadius(1),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          t(
            '强调色：已联网 · 灰色：未知 · 暗红色：未联网',
            'Accent: online · gray: unknown · red: offline',
          ),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        StatsSection(t('流量统计', 'Traffic totals')),
        NetworkDetailRow(
          t('累计下载：', 'Total download:'),
          formatNetworkBytes(ready ? telemetry.received : null),
        ),
        NetworkDetailRow(
          t('累计上传：', 'Total upload:'),
          formatNetworkBytes(ready ? telemetry.transmitted : null),
        ),
        NetworkDetailRow(t('互联网连接：', 'Internet connection:'), status),
        StatsSection(t('网络接口', 'Interfaces')),
        if (interfaces.isLoading)
          NetworkDetailRow(t('网卡信息', 'Interfaces'), t('正在读取…', 'Loading…')),
        for (final device in interfaces.value ?? []) ...[
          NetworkDetailRow(t('接口：', 'Interface:'), device.name),
          NetworkDetailRow(
            t('状态：', 'Status:'),
            device.state == 'up'
                ? t('已启用', 'Up')
                : device.state == 'down'
                ? t('已停用', 'Down')
                : device.state ?? '—',
          ),
          NetworkDetailRow(t('物理地址：', 'Physical address:'), device.mac ?? '—'),
          if (device.megabits != null)
            NetworkDetailRow(
              t('链路速率：', 'Link speed:'),
              '${device.megabits} Mb/s',
            ),
          if (device.addresses.isEmpty)
            NetworkDetailRow(t('本机地址：', 'Local address:'), '—'),
          for (final address in device.addresses)
            NetworkDetailRow(
              address.contains(':') ? 'IPv6:' : 'IPv4:',
              address,
            ),
          const SizedBox(height: 6),
        ],
        if (!interfaces.isLoading && (interfaces.value?.isEmpty ?? true))
          NetworkDetailRow(t('接口：', 'Interface:'), t('暂无接口', 'No interfaces')),
        if (wifi != null) ...[
          StatsSection('Wi-Fi'),
          NetworkDetailRow(t('网络：', 'Network:'), wifi.ssid),
          NetworkDetailRow(t('信号：', 'Signal:'), '${wifi.strength}%'),
          NetworkDetailRow(t('频率：', 'Frequency:'), '${wifi.frequency} MHz'),
          NetworkDetailRow(t('安全性：', 'Security:'), wifi.security.label),
        ],
        for (final error in [
          telemetry?.error,
          network.error,
          interfaces.hasError ? interfaces.error.toString() : null,
        ])
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error, style: TextStyle(color: colors.error)),
            ),
      ],
    );
  }
}

class _TrafficChart extends CustomPainter {
  _TrafficChart(this.history, this.peak, this.down, this.up, this.grid);
  final List<NetworkHistoryPoint> history;
  final double peak;
  final Color down;
  final Color up;
  final Color grid;
  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (history.length < 2) return;
    final first = history.first.time.inMicroseconds;
    final span = math.max(1, history.last.time.inMicroseconds - first);
    final scale = peak > 0 ? peak : 1.0;
    for (final download in [true, false]) {
      final color = download ? down : up;
      Path? line;
      double startX = 0;
      double endX = 0;
      void flush() {
        if (line == null) return;
        final fill = Path.from(line!)
          ..lineTo(endX, mid)
          ..lineTo(startX, mid)
          ..close();
        canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .22));
        canvas.drawPath(
          line!,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
        line = null;
      }

      for (final point in history) {
        if (point.speed == null) {
          flush();
          continue;
        }
        final x = (point.time.inMicroseconds - first) / span * size.width;
        final value = download ? point.speed!.download : point.speed!.upload;
        final y =
            mid + (download ? -1 : 1) * (value / scale).clamp(0, 1) * (mid - 2);
        if (line == null) {
          startX = x;
          line = Path()..moveTo(x, y);
        } else {
          line!.lineTo(x, y);
        }
        endX = x;
      }
      flush();
    }
  }

  @override
  bool shouldRepaint(_TrafficChart old) =>
      history != old.history ||
      peak != old.peak ||
      down != old.down ||
      up != old.up ||
      grid != old.grid;
}
