import 'dart:async';
import 'dart:io';

import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'control_center_profile.dart';

final _profileProvider = FutureProvider.autoDispose<ControlCenterProfile>((
  ref,
) {
  return readControlCenterProfile(ref.watch(startupEnvironmentProvider).values);
});

enum _Detail { notifications, power }

class ControlCenterHeader extends ConsumerStatefulWidget {
  const ControlCenterHeader({required this.onOpenSettings, super.key});
  final VoidCallback? onOpenSettings;
  @override
  ConsumerState<ControlCenterHeader> createState() =>
      _ControlCenterHeaderState();
}

class _ControlCenterHeaderState extends ConsumerState<ControlCenterHeader> {
  _Detail? _detail;
  SessionPowerController? _power;
  ProviderContainer? _container;
  bool _ownsConfirmation = false;

  void _cancelConfirmation() {
    if (_ownsConfirmation) _power?.cancelConfirmation();
    _ownsConfirmation = false;
  }

  void _toggle(_Detail detail) {
    _cancelConfirmation();
    setState(() => _detail = _detail == detail ? null : detail);
    if (_detail == _Detail.power) {
      _power = ref.read(sessionPowerProvider.notifier);
      unawaited(_power!.refresh());
    } else if (_detail == _Detail.notifications) {
      ref.read(desktopNotificationsProvider.notifier).markAllRead();
    }
  }

  @override
  void dispose() {
    // A popup can unmount during a build. Reconcile shared session state after
    // that build, and never write through a notifier disposed with the shell.
    final power = _power;
    final container = _container;
    if (_ownsConfirmation && power != null && container != null) {
      scheduleMicrotask(() {
        try {
          if (container.exists(sessionPowerProvider) &&
              identical(container.read(sessionPowerProvider.notifier), power)) {
            power.cancelConfirmation();
          }
        } on StateError {
          // The complete shell/provider scope was already released.
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _container = ProviderScope.containerOf(context, listen: false);
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    String label(String zh, String en) => chinese ? zh : en;
    final profile = ref.watch(_profileProvider).value;
    final name = profile?.name.isNotEmpty == true
        ? profile!.name
        : label('当前用户', 'Current user');
    final accent = context.shellTheme.accentPalette;
    final notifications = ref.watch(desktopNotificationsProvider);
    final header = Row(
      children: [
        Expanded(
          child: Tooltip(
            message: name,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.container,
                    border: Border.all(color: context.shellColors.hairlineSoft),
                  ),
                  child: profile?.avatarPath == null
                      ? Icon(
                          Icons.person_rounded,
                          color: accent.onContainer,
                          size: 22,
                        )
                      : Image.file(
                          File(profile!.avatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.person_rounded,
                            color: accent.onContainer,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.shellTheme.text.cardTitle.copyWith(
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        ControlCenterIconButton(
          label: [
            notifications.doNotDisturb
                ? label('勿扰已开启', 'Do not disturb is on')
                : label('通知', 'Notifications'),
            if (notifications.unreadCount > 0)
              label(
                '${notifications.unreadCount} 条未读',
                '${notifications.unreadCount} unread',
              ),
          ].join(' · '),
          icon: notifications.doNotDisturb
              ? Icons.notifications_off_rounded
              : Icons.notifications_none_rounded,
          unread: notifications.unreadCount > 0,
          active:
              _detail == _Detail.notifications || notifications.doNotDisturb,
          onPressed: () => _toggle(_Detail.notifications),
        ),
        const SizedBox(width: 7),
        ControlCenterIconButton(
          label: label('设置', 'Settings'),
          icon: Icons.settings_rounded,
          onPressed: widget.onOpenSettings,
        ),
        const SizedBox(width: 7),
        ControlCenterIconButton(
          label: label('电源', 'Power'),
          icon: Icons.power_settings_new_rounded,
          active: _detail == _Detail.power,
          onPressed: () => _toggle(_Detail.power),
        ),
      ],
    );
    final scale = ref.watch(
      shellSettingsProvider.select((s) => s.animations.durationScale),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Duration(
                  microseconds: (Motion.cardSettle.inMicroseconds * scale)
                      .round(),
                ),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.antiAlias,
          child: _detail == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _detail == _Detail.notifications
                      ? _NotificationsDetail(
                          onClose: () => _toggle(_Detail.notifications),
                        )
                      : _PowerDetail(
                          onClose: () => _toggle(_Detail.power),
                          onRequest: (action) {
                            _power = ref.read(sessionPowerProvider.notifier);
                            _ownsConfirmation = action.requiresConfirmation;
                            unawaited(_power!.request(action));
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

/// Same neutral surfaces, dimensions and accent roles as the dashboard header.
class ControlCenterIconButton extends StatelessWidget {
  const ControlCenterIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.unread = false,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool unread;
  @override
  Widget build(BuildContext context) {
    final shell = context.shellTheme;
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: active
              ? shell.accentPalette.container
              : context.shellColors.surfaceContainerHigh,
          foregroundColor: active
              ? shell.accentPalette.onContainer
              : context.shellColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: shell.borderRadius(12)),
        ),
        icon: Badge(
          isLabelVisible: unread,
          backgroundColor: shell.accentPalette.primary,
          smallSize: 6,
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.shellTheme.cardColor(
        context.shellColors.surfaceContainerLow,
      ),
      borderRadius: context.shellTheme.borderRadius(20),
      border: Border.all(color: context.shellColors.hairlineSoft),
    ),
    padding: const EdgeInsets.all(12),
    child: child,
  );
}

class _NotificationsDetail extends ConsumerWidget {
  const _NotificationsDetail({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    String label(String zh, String en) => chinese ? zh : en;
    final state = ref.watch(desktopNotificationsProvider);
    final controller = ref.read(desktopNotificationsProvider.notifier);
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label('通知', 'Notifications'),
                  style: context.shellTheme.text.cardTitle,
                ),
              ),
              IconButton(
                tooltip: label('清空通知', 'Clear notifications'),
                onPressed: state.history.isEmpty ? null : controller.clearAll,
                icon: const Icon(Icons.clear_all_rounded, size: 20),
              ),
              IconButton(
                tooltip: label('收起', 'Collapse'),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(label('勿扰模式', 'Do not disturb')),
            value: state.doNotDisturb,
            onChanged: controller.setDoNotDisturb,
          ),
          if (state.history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                label('暂无通知', 'No notifications'),
                textAlign: TextAlign.center,
              ),
            ),
          for (final record in state.history.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                record.notification.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  record.notification.appName,
                  record.notification.body,
                ].where((s) => s.isNotEmpty).join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: label('移除通知', 'Remove notification'),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () =>
                    controller.dismissFromHistory(record.notification.id),
              ),
              onTap: record.active
                  ? () => controller.invokeDefaultAction(record.notification.id)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _PowerDetail extends ConsumerWidget {
  const _PowerDetail({required this.onClose, required this.onRequest});
  final VoidCallback onClose;
  final ValueChanged<SessionPowerAction> onRequest;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    String label(String zh, String en) => chinese ? zh : en;
    final state = ref.watch(sessionPowerProvider);
    final controller = ref.read(sessionPowerProvider.notifier);
    String actionLabel(SessionPowerAction action) => switch (action) {
      SessionPowerAction.lock => label('锁屏', 'Lock'),
      SessionPowerAction.logout => label('注销', 'Log out'),
      SessionPowerAction.suspend => label('挂起', 'Suspend'),
      SessionPowerAction.hibernate => label('休眠', 'Hibernate'),
      SessionPowerAction.reboot => label('重启', 'Restart'),
      SessionPowerAction.powerOff => label('关机', 'Shut down'),
    };
    final confirmation = state.confirmationAction;
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label('电源与会话', 'Power and session'),
                  style: context.shellTheme.text.cardTitle,
                ),
              ),
              IconButton(
                tooltip: label('收起', 'Collapse'),
                onPressed: state.busy ? null : onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (confirmation != null) ...[
            Text(
              label(
                '确认${actionLabel(confirmation)}？',
                '${actionLabel(confirmation)}?',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: state.busy ? null : controller.cancelConfirmation,
                  child: Text(label('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: state.busy
                      ? null
                      : () => unawaited(controller.confirm()),
                  child: Text(label('确认', 'Confirm')),
                ),
              ],
            ),
          ] else
            for (final action in SessionPowerAction.values.where(
              (action) => action != SessionPowerAction.hibernate,
            ))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(actionLabel(action)),
                subtitle:
                    state.availabilityFor(action).unavailableReason == null
                    ? null
                    : Text(state.availabilityFor(action).unavailableReason!),
                enabled: !state.busy && state.availabilityFor(action).enabled,
                onTap: () => onRequest(action),
              ),
        ],
      ),
    );
  }
}
