// Layout inspired by Stats (MIT), Copyright (c) 2019 Serhiy Mytrovtsiy.
// See third_party/stats-LICENSE.
import 'dart:async';

import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'battery_presentation.dart';
import 'stats_panel.dart';
import 'power_mode_selector.dart';
import 'power_supply_state.dart';
import 'power_supply_readings.dart';

class BatteryPanel extends ConsumerWidget {
  const BatteryPanel({required this.onClose, super.key});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(batteryProvider);
    final details = ref.watch(upowerProvider);
    final modes = ref.watch(desktopPowerModesProvider);
    final snapshot = details.snapshot;
    final electrical = ref.watch(powerSupplyReadingsProvider);
    final supplies = electrical.isLoading || electrical.hasError
        ? const <SupplyReading>[]
        : electrical.value ?? const <SupplyReading>[];
    final inputReadings = displayedSupplyReadings(supplies);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String cn, String en) => zh ? cn : en;
    final capacity = battery.capacity;
    final plugged = snapshot == null ? null : !snapshot.onBattery;
    String number(double? value, String unit, [int digits = 2]) =>
        value == null || !value.isFinite
        ? '—'
        : '${value.toStringAsFixed(digits)} $unit';
    SupplyReading? supplyFor(UPowerBattery item) => supplies
        .where((s) => s.battery && s.name == item.nativePath.split('/').last)
        .firstOrNull;
    String remaining(Duration? value) {
      if (value == null || value.inSeconds <= 0) return '—';
      return zh
          ? '${value.inHours}小时 ${value.inMinutes.remainder(60)}分钟'
          : '${value.inHours}h ${value.inMinutes.remainder(60)}m';
    }

    final status = capacity == null
        ? t('状态未知', 'Unknown')
        : battery.charging
        ? t('正在充电', 'Charging')
        : capacity == 100
        ? t('已充满', 'Fully charged')
        : plugged == true
        ? t('暂停充电', 'On hold')
        : plugged == false
        ? t('使用电池', 'On battery')
        : t('未充电', 'Not charging');
    return StatsPanel(
      title: t('电池', 'Battery'),
      icon: Icons.bar_chart_rounded,
      onClose: onClose,
      onRefresh: () {
        ref.invalidate(powerSupplyReadingsProvider);
        if (!details.refreshing) {
          unawaited(ref.read(upowerProvider.notifier).refresh());
        }
        if (!modes.refreshing && !modes.systemChanging) {
          unawaited(ref.read(desktopPowerModesProvider.notifier).refresh());
        }
      },
      children: [
        const SizedBox(height: 25),
        Center(
          child: Semantics(
            label: '${t('电量', 'Battery level')} ${capacity ?? '—'}',
            child: SizedBox(
              width: 150,
              height: 72,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 2,
                    bottom: 2,
                    right: 7,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: .05),
                            ),
                            if (capacity != null)
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: capacity.clamp(0, 100) / 100,
                                child: ColoredBox(
                                  color: context.shellTheme.accent,
                                ),
                              ),
                            Center(
                              child: Icon(
                                plugged == true
                                    ? Icons.power_rounded
                                    : battery.charging
                                    ? Icons.bolt_rounded
                                    : Icons.battery_std_rounded,
                                color: capacity != null && capacity >= 50
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 25,
                    width: 4,
                    height: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: capacity == null ? '—' : '$capacity',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (capacity != null)
                  TextSpan(
                    text: '%',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 3, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .08),
              borderRadius: context.shellTheme.borderRadius(6),
            ),
            child: Text(status, style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
        StatsSection(t('详细信息', 'Details')),
        StatsRow(
          t('电源来源：', 'Source:'),
          plugged == null
              ? '—'
              : plugged
              ? t('外接电源', 'AC Power')
              : t('电池', 'Battery'),
        ),
        if (details.loading)
          StatsRow(t('电池详情', 'Battery details'), t('正在读取…', 'Loading…')),
        for (final item in snapshot?.batteries ?? <UPowerBattery>[]) ...[
          StatsRow(
            battery.charging
                ? t('充满所需时间：', 'Time to charge:')
                : t('剩余使用时间：', 'Time to discharge:'),
            remaining(battery.charging ? item.timeToFull : item.timeToEmpty),
          ),
          StatsSection(
            (snapshot!.batteries.length > 1
                ? '${t('电池', 'Battery')} · ${item.displayName}'
                : t('电池', 'Battery')),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('满充容量', 'Max capacity'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      number(item.energyFull, 'Wh'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      t('设计容量', 'Designed capacity'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      number(item.energyFullDesign, 'Wh'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (item.healthPercentage != null)
            LinearProgressIndicator(
              value: (item.healthPercentage! / 100).clamp(0, 1),
              minHeight: 6,
            ),
          const SizedBox(height: 6),
          StatsRow(t('功率：', 'Power:'), number(item.energyRate, 'W')),
          StatsRow(
            supplyFor(item)?.amps != null &&
                    supplyFor(item)?.estimatedAmps == false
                ? t('电流：', 'Current:')
                : t('电流（估算）：', 'Current (est.):'),
            number(
              supplyFor(item)?.amps != null
                  ? supplyFor(item)!.amps! * 1000
                  : estimatedBatteryCurrent(item.energyRate, item.voltage),
              'mA',
              0,
            ),
          ),
          StatsRow(t('电压：', 'Voltage:'), number(item.voltage, 'V')),
          StatsRow(t('健康度：', 'Health:'), number(item.healthPercentage, '%', 0)),
          StatsRow(t('循环次数：', 'Cycles:'), item.chargeCycles?.toString() ?? '—'),
          StatsRow(t('温度：', 'Temperature:'), number(item.temperature, '°C', 1)),
        ],
        if (!details.loading && (snapshot?.batteries.isEmpty ?? true))
          StatsRow(t('电池详情', 'Battery details'), t('不可用', 'Unavailable')),
        if (plugged == true) ...[
          StatsSection(t('电源适配器', 'Power adapter')),
          StatsRow(
            t('正在充电：', 'Is charging:'),
            capacity == null
                ? '—'
                : battery.charging
                ? t('是', 'Yes')
                : t('否', 'No'),
          ),
          if (electrical.isLoading)
            StatsRow(t('电气读数', 'Electrical readings'), t('正在读取…', 'Loading…')),
          for (final supply in inputReadings) ...[
            StatsRow(
              t('读数来源：', 'Readings from:'),
              '${supply.battery ? t('电池充电侧', 'Battery charging side') : t('适配器', 'Adapter')} · ${supply.name}',
            ),
            StatsRow(
              supply.estimatedWatts
                  ? t('功率（估算）：', 'Power (est.):')
                  : t('功率：', 'Power:'),
              number(supply.watts, 'W'),
            ),
            StatsRow(
              supply.estimatedAmps
                  ? t('电流（估算）：', 'Current (est.):')
                  : t('电流：', 'Current:'),
              number(supply.amps == null ? null : supply.amps! * 1000, 'mA', 0),
            ),
            StatsRow(t('电压：', 'Voltage:'), number(supply.volts, 'V')),
          ],
          if (!electrical.isLoading && inputReadings.isEmpty) ...[
            StatsRow(t('功率：', 'Power:'), '—'),
            StatsRow(t('电流：', 'Current:'), '—'),
            StatsRow(t('电压：', 'Voltage:'), '—'),
          ],
          if (inputReadings.isNotEmpty && inputReadings.every((s) => s.battery))
            Text(
              t(
                '适配器未上报读数，以上为电池充电侧数据',
                'Adapter readings unavailable; showing battery-side data',
              ),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          if (!electrical.isLoading && inputReadings.isEmpty)
            Text(
              t('设备未上报电气读数', 'Device reports no electrical readings'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          if (electrical.hasError)
            Text(
              t('无法读取电源数据：', 'Could not read power data: ') +
                  electrical.error.toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
        StatsSection(t('性能模式', 'Power mode')),
        const PowerModeSelector(),
        for (final error in [details.error])
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
      ],
    );
  }
}
