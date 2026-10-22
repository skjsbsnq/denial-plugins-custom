import 'dart:async';

import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'battery_presentation.dart';
import 'panel_content_transition.dart';

class PowerModeSelector extends ConsumerStatefulWidget {
  const PowerModeSelector({super.key});
  @override
  ConsumerState<PowerModeSelector> createState() => _PowerModeSelectorState();
}

class _PowerModeSelectorState extends ConsumerState<PowerModeSelector> {
  String? _pending;

  Future<void> _select(String profile) async {
    final state = ref.read(desktopPowerModesProvider);
    if (_pending != null ||
        !state.systemAvailable ||
        state.systemChanging ||
        state.refreshing ||
        state.systemProfile == profile) {
      return;
    }
    setState(() => _pending = profile);
    try {
      await ref
          .read(desktopPowerModesProvider.notifier)
          .selectSystemProfile(profile);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopPowerModesProvider);
    final shell = context.shellTheme;
    final colors = Theme.of(context).colorScheme;
    final duration = panelInteractionDuration(
      context,
      ref.watch(shellSettingsProvider).animations.durationScale,
    );
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String cn, String en) => zh ? cn : en;
    final profiles = [
      (PowerProfile.powerSave, t('省电', 'Power saver'), Icons.eco_rounded),
      (PowerProfile.balanced, t('均衡', 'Balanced'), Icons.balance_rounded),
      (PowerProfile.performance, t('性能', 'Performance'), Icons.speed_rounded),
    ];
    final presentation = PowerModePresentation(
      available: state.systemAvailable,
      refreshing: state.refreshing,
      changing: state.systemChanging,
      profile: state.systemProfile,
    );
    final index = state.systemAvailable
        ? profiles.indexWhere((p) => p.$1 == state.systemProfile)
        : -1;
    final busy = _pending != null || state.systemChanging;
    final canSelect = presentation.canSelect && !busy;
    final message =
        state.error ??
        (busy
            ? '${t('正在切换', 'Switching')}${_pending == null ? '' : ' · ${profiles.firstWhere((p) => p.$1 == _pending).$2}'}…'
            : state.refreshing
            ? t('正在读取…', 'Loading…')
            : !state.systemAvailable
            ? t('系统性能模式不可用', 'System power modes unavailable')
            : '${t('当前模式', 'Current mode')} · ${profiles.where((p) => p.$1 == state.systemProfile).firstOrNull?.$2 ?? '—'}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: .05),
            borderRadius: shell.borderRadius(12),
          ),
          child: Stack(
            children: [
              if (index >= 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedAlign(
                      alignment: Alignment(index - 1.0, 0),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: FractionallySizedBox(
                        widthFactor: 1 / 3,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: shell.accent.withValues(alpha: .18),
                            borderRadius: shell.borderRadius(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final profile in profiles)
                    Expanded(
                      child: Semantics(
                        selected: presentation.isSelected(profile.$1),
                        child: InkWell(
                          onTap: canSelect
                              ? () => unawaited(_select(profile.$1))
                              : null,
                          borderRadius: shell.borderRadius(10),
                          child: AnimatedContainer(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: shell.borderRadius(10),
                              border: Border.all(
                                color: _pending == profile.$1
                                    ? shell.accent
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: _pending == profile.$1
                                      ? MediaQuery.disableAnimationsOf(
                                                  context,
                                                ) ||
                                                duration == Duration.zero
                                            ? Icon(
                                                Icons.more_horiz_rounded,
                                                color: shell.accent,
                                                size: 20,
                                              )
                                            : CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: shell.accent,
                                              )
                                      : Icon(
                                          profile.$3,
                                          size: 20,
                                          color:
                                              presentation.isSelected(
                                                profile.$1,
                                              )
                                              ? shell.accent
                                              : colors.onSurfaceVariant,
                                        ),
                                ),
                                const SizedBox(height: 6),
                                AnimatedDefaultTextStyle(
                                  duration: duration,
                                  style:
                                      (Theme.of(context)
                                                  .textTheme
                                                  .labelMedium ??
                                              const TextStyle())
                                          .copyWith(
                                            color:
                                                presentation.isSelected(
                                                  profile.$1,
                                                )
                                                ? shell.accent
                                                : colors.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                  child: Text(
                                    profile.$2,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
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
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: state.error == null
                  ? colors.onSurfaceVariant
                  : colors.error,
            ),
          ),
        ),
      ],
    );
  }
}
