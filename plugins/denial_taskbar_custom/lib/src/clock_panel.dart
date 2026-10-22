// Layout inspired by Stats (MIT), Copyright (c) 2019 Serhiy Mytrovtsiy.
// See third_party/stats-LICENSE.
import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_dates.dart';
import 'stats_panel.dart';
import 'panel_content_transition.dart';

class ClockPanel extends ConsumerStatefulWidget {
  const ClockPanel({required this.onClose, super.key});
  final VoidCallback onClose;
  @override
  ConsumerState<ClockPanel> createState() => _ClockPanelState();
}

class _ClockPanelState extends ConsumerState<ClockPanel> {
  late final Timer _seconds;
  final _time = ValueNotifier(DateTime.now());

  void _refreshTime() {
    final now = DateTime.now();
    // The calendar changes at midnight (also after a system date/time-zone
    // change), not on every second. Keep its in-flight transition untouched.
    if (!sameCalendarDay(_time.value, now)) setState(() {});
    _time.value = now;
  }

  @override
  void initState() {
    super.initState();
    // A visible-clock repaint only; no device reads or background service.
    _seconds = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _refreshTime();
    });
  }

  @override
  void dispose() {
    _seconds.cancel();
    _time.dispose();
    super.dispose();
  }

  int _direction = 1;
  DateTime? _month;
  DateTime? _selected;
  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    ref.listen(services.clock, (_, _) => _refreshTime());
    final now = _time.value;
    final month = _month ?? DateTime(now.year, now.month);
    final local = MaterialLocalizations.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final shell = context.shellTheme;
    final colors = Theme.of(context).colorScheme;
    final firstWeekday = local.firstDayOfWeekIndex;
    final days = calendarDates(month, firstWeekday: firstWeekday);
    String t(String cn, String en) => zh ? cn : en;
    void move(int delta) => setState(() {
      _direction = delta.sign;
      _month = DateTime(month.year, month.month + delta);
    });
    Widget inset(Widget child) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: .045),
        borderRadius: shell.borderRadius(6),
      ),
      child: child,
    );
    return StatsPanel(
      title: t('时钟', 'Clock'),
      icon: Icons.calendar_month_outlined,
      onClose: widget.onClose,
      children: [
        const SizedBox(height: 12),
        inset(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _direction =
                            DateTime(now.year, now.month).isBefore(month)
                            ? -1
                            : 1;
                        _month = null;
                        _selected = null;
                      }),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        foregroundColor: colors.onSurface,
                      ),
                      child: PanelContentTransition(
                        identity: DateTime(month.year, month.month),
                        direction: _direction,
                        child: Text(local.formatMonthYear(month)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t('上个月', 'Previous month'),
                    onPressed: () => move(-1),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    tooltip: t('下个月', 'Next month'),
                    onPressed: () => move(1),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              PanelContentTransition(
                identity: DateTime(month.year, month.month),
                direction: _direction,
                child: Table(
                  children: [
                    TableRow(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Text(
                              local.narrowWeekdays[(firstWeekday + i) % 7],
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                    for (var row = 0; row < 6; row++)
                      TableRow(
                        children: [
                          for (final day in days.skip(row * 7).take(7))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Semantics(
                                label: local.formatFullDate(day),
                                selected:
                                    _selected != null &&
                                    sameCalendarDay(day, _selected!),
                                child: TextButton(
                                  onPressed: () => setState(() {
                                    _direction = day.isBefore(month) ? -1 : 1;
                                    _selected = day;
                                    _month = DateTime(day.year, day.month);
                                  }),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 38),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: sameCalendarDay(day, now)
                                        ? shell.accent
                                        : Colors.transparent,
                                    shape: const CircleBorder(),
                                    side:
                                        _selected != null &&
                                            sameCalendarDay(day, _selected!)
                                        ? BorderSide(color: shell.accent)
                                        : BorderSide.none,
                                  ),
                                  child: Text(
                                    '${day.day}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: sameCalendarDay(day, now)
                                              ? colors.onPrimary
                                              : day.month == month.month
                                              ? colors.onSurface
                                              : colors.onSurface.withValues(
                                                  alpha: .38,
                                                ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        inset(
          RepaintBoundary(
            child: ValueListenableBuilder<DateTime>(
              valueListenable: _time,
              builder: (context, now, child) => _LocalTime(now: now),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalTime extends StatelessWidget {
  const _LocalTime({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shell = context.shellTheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String cn, String en) => zh ? cn : en;
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CustomPaint(
            painter: _ClockFace(now, colors.onSurface, shell.accent),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('本地时间', 'Local time'),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              Text(
                '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          utcOffsetLabel(now.timeZoneOffset),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _ClockFace extends CustomPainter {
  _ClockFace(this.time, this.foreground, this.accent);
  final DateTime time;
  final Color foreground;
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 1;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = foreground.withValues(alpha: .3)
        ..style = PaintingStyle.stroke,
    );
    void hand(double turns, double length) {
      final angle = turns * math.pi * 2 - math.pi / 2;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * radius * length,
        Paint()
          ..color = foreground
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    hand((time.hour % 12 + time.minute / 60) / 12, .5);
    hand(time.minute / 60, .78);
    final angle = time.second / 60 * math.pi * 2 - math.pi / 2;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * radius * .82,
      Paint()
        ..color = accent
        ..strokeWidth = .8,
    );
    canvas.drawCircle(center, 1.6, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_ClockFace oldDelegate) =>
      time != oldDelegate.time ||
      foreground != oldDelegate.foreground ||
      accent != oldDelegate.accent;
}
