import 'dart:async';

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'neutral_color.dart';
import 'battery_panel.dart';
import 'clock_panel.dart';
import 'network_panel.dart';
import 'control_center_layout.dart';
import 'control_center_header.dart';
import 'pixel_aligned_panel.dart';
import 'connectivity_menu.dart';
import 'volume_presentation.dart';
import 'anchored_menu_expansion.dart';
import 'control_center_reveal.dart';
import 'panel_motion.dart';
import 'popup_focus_feedback.dart';

enum _TaskbarPopupKind { controls, battery, clock, network }

/// Plugin-owned popup: it never opens or replaces the host Dashboard.
class ControlCenterButton extends ConsumerStatefulWidget {
  const ControlCenterButton({required this.monitorId, super.key})
    : _kind = _TaskbarPopupKind.controls,
      buttonChild = null;
  const ControlCenterButton.battery({required this.monitorId, super.key})
    : _kind = _TaskbarPopupKind.battery,
      buttonChild = null;
  const ControlCenterButton.clock({
    required this.monitorId,
    required Widget child,
    super.key,
  }) : _kind = _TaskbarPopupKind.clock,
       buttonChild = child;
  const ControlCenterButton.network({
    required this.monitorId,
    required Widget child,
    super.key,
  }) : _kind = _TaskbarPopupKind.network,
       buttonChild = child;
  final _TaskbarPopupKind _kind;
  final Widget? buttonChild;
  bool get battery => _kind == _TaskbarPopupKind.battery;
  bool get clock => _kind == _TaskbarPopupKind.clock;
  bool get network => _kind == _TaskbarPopupKind.network;
  final int monitorId;

  @override
  ConsumerState<ControlCenterButton> createState() =>
      _ControlCenterButtonState();
}

class _ControlCenterButtonState extends ConsumerState<ControlCenterButton>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _focus = FocusNode(debugLabel: 'Control center toggle');
  late final AnimationController _animation = AnimationController(vsync: this);
  Animation<double> get _progress => _animation;
  bool _open = false;
  double? _motionTarget;
  Future<bool>? _motionCompletion;

  Future<bool> _drivePanel(bool visible) {
    final target = visible ? 1.0 : 0.0;
    // Pointer-down, Escape and action callbacks can ask for the same close.
    // Share the running transition instead of repeatedly interrupting it.
    if (_motionTarget == target &&
        _animation.isAnimating &&
        _motionCompletion != null) {
      return _motionCompletion!;
    }
    final scale = ref.read(shellSettingsProvider).animations.durationScale;
    if (MediaQuery.disableAnimationsOf(context) || scale <= 0) {
      _animation.stop();
      _animation.value = target;
      _motionTarget = target;
      return Future.value(true);
    }
    final motion = PanelMotion(
      start: _animation.value,
      initialVelocity: _animation.velocity,
      target: target,
      durationScale: scale,
    );
    _motionTarget = target;
    final completion = _finishMotion(
      _animation.animateWith(_PanelSimulation(motion)).orCancel,
    );
    _motionCompletion = completion;
    return completion;
  }

  Future<bool> _finishMotion(Future<void> completion) async {
    try {
      await completion;
      return true;
    } on TickerCanceled {
      return false;
    }
  }

  void _toggle() {
    if (_open) {
      unawaited(_close());
      return;
    }
    if (widget.battery) {
      unawaited(ref.read(desktopPowerModesProvider.notifier).refresh());
    }
    setState(() {
      _open = true;
      _portal.show();
    });
    unawaited(_drivePanel(true));
  }

  Future<bool> _close({
    bool restoreFocus = true,
    bool immediate = false,
  }) async {
    if (!_portal.isShowing) return true;
    if (!_open && !_animation.isAnimating && _animation.value == 0) return true;
    setState(() => _open = false);
    if (immediate) {
      _animation.stop();
      _animation.value = 0;
    } else if (!await _drivePanel(false)) {
      return false;
    }
    if (!mounted || _open) return false;
    setState(_portal.hide);
    if (restoreFocus && _focus.context != null) _focus.requestFocus();
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ShellSurfacePresentation.visibleOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ShellSurfacePresentation.visibleOf(context)) {
          unawaited(_close(restoreFocus: false, immediate: true));
        }
      });
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    final bounds = ref.watch(services.monitorBounds(widget.monitorId));
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final keyboardFocus = ref.watch(popupFocusFeedbackProvider);
    final battery = widget.battery ? ref.watch(batteryProvider) : null;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) =>
          _buildPopup(context, layout, bounds),
      child: Listener(
        onPointerDown: (_) =>
            ref.read(popupFocusFeedbackProvider.notifier).pointerInteraction(),
        child: SizedBox(
          width: widget.buttonChild != null ? null : 40,
          child: Semantics(
            expanded: _open,
            child: widget.buttonChild != null
                ? TextButton(
                    focusNode: _focus,
                    onPressed: _toggle,
                    style: popupButtonFocusStyle(
                      TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: context.shellTheme.borderRadius(4),
                        ),
                      ),
                      keyboard: keyboardFocus,
                    ),
                    child: widget.buttonChild!,
                  )
                : IconButton(
                    focusNode: _focus,
                    tooltip: widget.battery
                        ? '${chinese ? '电池' : 'Battery'} ${battery?.capacity == null ? '—' : '${battery!.capacity}%'}'
                        : (chinese ? '控制中心' : 'Control center'),
                    onPressed: _toggle,
                    style: popupButtonFocusStyle(
                      IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        overlayColor: taskbarForeground(context)
                            .withValues(alpha: 0.10),
                        shape: RoundedRectangleBorder(
                          borderRadius: context.shellTheme.borderRadius(4),
                        ),
                      ),
                      keyboard: keyboardFocus,
                    ),
                    icon: Icon(
                      widget.battery
                          ? (battery?.charging == true
                                ? Icons.battery_charging_full_rounded
                                : battery?.capacity == null
                                ? Icons.battery_unknown_rounded
                                : battery!.capacity! <= 20
                                ? Icons.battery_1_bar_rounded
                                : battery.capacity! <= 50
                                ? Icons.battery_3_bar_rounded
                                : battery.capacity! <= 80
                                ? Icons.battery_5_bar_rounded
                                : Icons.battery_full_rounded)
                          : Icons.tune_rounded,
                      color: taskbarForeground(context),
                      size: 22,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopup(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    Rect? bounds,
  ) {
    final output = (bounds ?? (Offset.zero & layout.overlaySize)).intersect(
      Offset.zero & layout.overlaySize,
    );
    final placement = controlCenterLayout(
      outputLeft: output.left,
      outputTop: output.top,
      outputRight: output.right,
      outputBottom: output.bottom,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      panelWidth: widget.battery || widget.clock || widget.network
          ? statsPanelWidth
          : 420,
    );
    if (placement == null) return const SizedBox.shrink();
    final travel = ref.watch(
      shellSettingsProvider.select((s) => s.animations.panelTravel),
    );
    return Listener(
      onPointerDown: (_) =>
          ref.read(popupFocusFeedbackProvider.notifier).pointerInteraction(),
      child: ShellInputRegion(
        debugLabel: widget.network
            ? 'Custom network card'
            : widget.clock
            ? 'Custom clock card'
            : widget.battery
            ? 'Custom battery card'
            : 'Custom control center',
        active: _open,
        pointerPolicy: ShellPointerPolicy.fullScene,
        keyboardPolicy: _open
            ? ShellKeyboardPolicy.capture
            : ShellKeyboardPolicy.none,
        child: IgnorePointer(
          ignoring: !_open,
          child: ExcludeSemantics(
            excluding: !_open,
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              },
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (_) {
                      unawaited(_close());
                      return null;
                    },
                  ),
                },
                child: FocusScope(
                  autofocus: true,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) =>
                              unawaited(_close(restoreFocus: false)),
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                      // Clip panel travel to this monitor, including on multi-output desktops.
                      Positioned.fromRect(
                        rect: output,
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Positioned(
                                right: output.right - placement.right,
                                bottom: output.bottom - placement.bottom,
                                width: placement.width,
                                child: ControlCenterReveal(
                                  progress: _progress,
                                  travel: travel,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: placement.maxHeight,
                                    ),
                                    child: Theme(
                                      data: context.shellTheme
                                          .toMaterialTheme(),
                                      child: PixelAlignedPanel(
                                        devicePixelRatio:
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ),
                                        child: widget.network
                                            ? NetworkPanel(
                                                onClose: () =>
                                                    unawaited(_close()),
                                              )
                                            : widget.clock
                                            ? ClockPanel(
                                                onClose: () =>
                                                    unawaited(_close()),
                                              )
                                            : widget.battery
                                            ? BatteryPanel(
                                                onClose: () =>
                                                    unawaited(_close()),
                                              )
                                            : _ControlCenterPanel(
                                                monitorId: widget.monitorId,
                                                onClose: () => _close(),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlCenterPanel extends ConsumerStatefulWidget {
  const _ControlCenterPanel({required this.monitorId, required this.onClose});
  final int monitorId;
  final Future<bool> Function() onClose;

  @override
  ConsumerState<_ControlCenterPanel> createState() =>
      _ControlCenterPanelState();
}

class _ControlCenterPanelState extends ConsumerState<_ControlCenterPanel>
    with SingleTickerProviderStateMixin {
  ConnectivityMenuKind? _detail;
  ConnectivityMenuKind _displayedDetail = ConnectivityMenuKind.wifi;
  final _menuBodyKey = GlobalKey();
  final _menuViewportKey = GlobalKey();
  final _wifiDetailsKey = GlobalKey();
  final _bluetoothDetailsKey = GlobalKey();
  final _wifiDetailsFocus = FocusNode(debugLabel: 'Wi-Fi details toggle');
  final _bluetoothDetailsFocus = FocusNode(
    debugLabel: 'Bluetooth details toggle',
  );
  final _detailFocus = FocusNode(debugLabel: 'Expanded connectivity menu');
  final _menuTransitionFocus = FocusNode(
    debugLabel: 'Connectivity menu transition',
  );
  late final AnimationController _menuExpansion = AnimationController(
    vsync: this,
  );
  late final CurvedAnimation _menuMotion = CurvedAnimation(
    parent: _menuExpansion,
    curve: Motion.md3EmphasizedDecelerate,
    reverseCurve: Motion.md3EmphasizedAccelerate,
  );
  Rect _menuOrigin = Rect.zero;
  Rect _menuTarget = Rect.zero;
  final _scroll = ScrollController();
  final _volume = VolumePresentation();
  StreamSubscription<AudioLevelState>? _audioSubscription;
  Timer? _volumeReconciliation;
  bool _volumeReadFailed = false;

  @override
  void initState() {
    super.initState();
    final audio = ref.read(audioServiceProvider);
    _audioSubscription = audio.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _volume.nativeState(state.level, isMuted: state.muted);
        _volumeReadFailed = false;
      });
      if (!_volume.needsReconciliation) _volumeReconciliation?.cancel();
    });
    scheduleMicrotask(_readVolume);
  }

  Future<void> _readVolume() async {
    if (!mounted) return;
    final audio = ref.read(audioServiceProvider);
    final token = _volume.beginRead();
    try {
      final value = await audio.readLevel();
      if (!mounted) return;
      setState(() {
        _volume.completeRead(token, value);
        _volumeReadFailed = _volume.level == null && value == null;
      });
    } on Object {
      if (mounted) setState(() => _volumeReadFailed = _volume.level == null);
    }
  }

  void _beginVolume(ShellServices services) {
    _volumeReconciliation?.cancel();
    _volume.beginInteraction();
    services.beginVolumeInteraction();
  }

  void _setVolume(ShellServices services, double value) {
    setState(() => _volume.intent(value));
    services.setVolume(value);
  }

  void _commitVolume(ShellServices services, double value) {
    setState(() => _volume.commit(value));
    services.commitVolume(value);
    _volumeReconciliation?.cancel();
    _volumeReconciliation = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_volume.needsReconciliation) return;
      _volume.reconcile();
      unawaited(_readVolume());
    });
  }

  @override
  void dispose() {
    unawaited(_audioSubscription?.cancel());
    _volumeReconciliation?.cancel();
    _menuMotion.dispose();
    _menuExpansion.dispose();
    _wifiDetailsFocus.dispose();
    _bluetoothDetailsFocus.dispose();
    _detailFocus.dispose();
    _menuTransitionFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _backToControls() {
    final detail = _detail;
    if (detail == null) return;
    final buttonKey = detail == ConnectivityMenuKind.wifi
        ? _wifiDetailsKey
        : _bluetoothDetailsKey;
    final button = buttonKey.currentContext?.findRenderObject();
    final body = _menuBodyKey.currentContext?.findRenderObject();
    if (button is RenderBox && body is RenderBox) {
      _menuOrigin =
          body.globalToLocal(button.localToGlobal(Offset.zero)) & button.size;
    }
    setState(() => _detail = null);
    _menuExpansion.reverse().whenCompleteOrCancel(() {
      if (!mounted || _detail != null || _menuExpansion.value != 0) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _detail != null || _menuExpansion.value != 0) return;
        (detail == ConnectivityMenuKind.wifi
                ? _wifiDetailsFocus
                : _bluetoothDetailsFocus)
            .requestFocus();
      });
    });
  }

  int get monitorId => widget.monitorId;
  Future<bool> Function() get onClose => widget.onClose;

  void _showDetail(ConnectivityMenuKind kind) {
    final buttonKey = kind == ConnectivityMenuKind.wifi
        ? _wifiDetailsKey
        : _bluetoothDetailsKey;
    final button = buttonKey.currentContext?.findRenderObject();
    final body = _menuBodyKey.currentContext?.findRenderObject();
    final viewport = _menuViewportKey.currentContext?.findRenderObject();
    if (button is! RenderBox || body is! RenderBox) return;
    _menuOrigin =
        body.globalToLocal(button.localToGlobal(Offset.zero)) & button.size;
    _menuTarget = Offset.zero & body.size;
    if (viewport is RenderBox) {
      final bounds = menuViewportBounds(
        bodyHeight: body.size.height,
        bodyTopInViewport: viewport
            .globalToLocal(body.localToGlobal(Offset.zero))
            .dy,
        viewportHeight: viewport.size.height,
      );
      if (bounds != null) {
        _menuTarget = Rect.fromLTRB(
          0,
          bounds.top,
          body.size.width,
          bounds.bottom,
        );
      }
    }
    setState(() {
      _detail = kind;
      _displayedDetail = kind;
    });
    _menuTransitionFocus.requestFocus();
    _menuExpansion.forward().whenCompleteOrCancel(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _detail == kind && _menuExpansion.value == 1) {
          _detailFocus.requestFocus();
        }
      });
    });
    if (kind == ConnectivityMenuKind.wifi) {
      unawaited(ref.read(networkConnectivityProvider.notifier).scan());
    } else {
      unawaited(ref.read(bluetoothProvider.notifier).scan());
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    final shell = context.shellTheme;
    final colors = Theme.of(context).colorScheme;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    String label(String zh, String en) => chinese ? zh : en;
    final volume = _volume.level;
    final audio = ref.watch(audioDevicesProvider);
    final network = ref.watch(networkConnectivityProvider);
    final bluetooth = ref.watch(bluetoothProvider);
    final displays = ref.watch(displayLayoutProvider)?.outputs;
    final output = displays
        ?.where((item) => item.monitorId == monitorId)
        .firstOrNull;
    final brightness = ref.watch(displayBrightnessProvider);
    final level = brightness.levels[monitorId];
    final dark = shell.brightness == Brightness.dark;
    final radius = BorderRadius.circular(shell.panelRadius);
    final animationScale = ref.watch(
      shellSettingsProvider.select((s) => s.animations.durationScale),
    );
    _menuExpansion.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: (250 * animationScale).round());
    _menuExpansion.reverseDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: (200 * animationScale).round());
    final wifiAvailable =
        !network.initializing &&
        !network.radioChanging &&
        network.snapshot.serviceAvailable &&
        network.snapshot.wifiDeviceAvailable &&
        network.snapshot.wirelessHardwareEnabled &&
        network.snapshot.radioPermission != NetworkPermission.denied;

    void closeThen(VoidCallback action) {
      unawaited(
        onClose().then((closed) {
          if (closed) action();
        }),
      );
    }

    void openSettings() {
      // Settings is a standalone application in current Denial installations,
      // not an entry in the shell's local Flutter application registry.
      final environment = ref.read(startupEnvironmentProvider);
      final configured = environment['DENIAL_SETTINGS_BINARY']?.trim();
      final executable = configured == null || configured.isEmpty
          ? 'denial-settings'
          : configured;
      final bridge = ref.read(denialBridgeProvider);
      final existing = ref
          .read(shellControllerProvider)
          .windows
          .where(
            (window) =>
                window.isUserApp &&
                window.appId.trim().toLowerCase() == 'dev.denial.settings',
          )
          .firstOrNull;
      closeThen(() {
        if (existing != null) {
          services.activateWindow(existing.objectId);
        } else {
          bridge.launchApplication([executable]);
        }
      });
    }

    return ShellBackdropBlur(
      blur: shell.effectivePanelOpacity < 1,
      // Filter only the background. Foreground glyphs and controls must not
      // enter the backdrop's intermediate color layer or be resampled with it.
      separateChild: true,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shell.panelColor(context.shellColors.panelBackground),
          borderRadius: radius,
        ),
        child: RepaintBoundary(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              key: _menuViewportKey,
              physics: _detail != null || _menuExpansion.value > 0
                  ? const NeverScrollableScrollPhysics()
                  : null,
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ControlCenterHeader(onOpenSettings: openSettings),
                  const SizedBox(height: 12),
                  AnchoredMenuExpansion(
                    key: _menuBodyKey,
                    animation: _menuMotion,
                    open: _detail != null,
                    origin: _menuOrigin,
                    target: _menuTarget,
                    transitionFocus: _menuTransitionFocus,
                    onBack: _backToControls,
                    detailFocus: _detailFocus,
                    detail: ConnectivityMenu(
                      key: ValueKey(_displayedDetail),
                      kind: _displayedDetail,
                      onBack: _backToControls,
                    ),
                    controls: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SectionTitle(
                                title: label('声音', 'Sound'),
                                value: volume == null
                                    ? '—'
                                    : '${(volume * 100).round()} %',
                              ),
                              Row(
                                children: [
                                  Icon(
                                    volume == 0
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: volume ?? 0,
                                      label: volume == null
                                          ? null
                                          : '${(volume * 100).round()} %',
                                      semanticFormatterCallback: (value) =>
                                          '${(value * 100).round()} %',
                                      onChangeStart: volume == null
                                          ? null
                                          : (_) => _beginVolume(services),
                                      onChanged: volume == null
                                          ? null
                                          : (value) =>
                                                _setVolume(services, value),
                                      onChangeEnd: volume == null
                                          ? null
                                          : (value) =>
                                                _commitVolume(services, value),
                                    ),
                                  ),
                                ],
                              ),
                              if (volume == null)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _volumeReadFailed
                                            ? label(
                                                '无法读取音量',
                                                'Unable to read volume',
                                              )
                                            : label(
                                                '正在读取音量…',
                                                'Reading volume…',
                                              ),
                                      ),
                                    ),
                                    if (_volumeReadFailed)
                                      IconButton(
                                        tooltip: label('重试', 'Retry'),
                                        onPressed: () =>
                                            unawaited(_readVolume()),
                                        icon: const Icon(Icons.refresh_rounded),
                                      ),
                                  ],
                                ),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                shape: const Border(),
                                collapsedShape: const Border(),
                                leading: const Icon(Icons.speaker_rounded),
                                title: Text(label('输出设备', 'Output device')),
                                subtitle: Text(
                                  audio.loading
                                      ? label('正在加载…', 'Loading…')
                                      : audio.activeDevice?.description ??
                                            label(
                                              '无可用输出设备',
                                              'No output device',
                                            ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                children: [
                                  for (final device in audio.devices)
                                    ListTile(
                                      dense: true,
                                      title: Text(device.description),
                                      trailing: device.active
                                          ? const Icon(Icons.check_rounded)
                                          : null,
                                      enabled:
                                          device.available && !audio.changing,
                                      onTap: () => ref
                                          .read(audioDevicesProvider.notifier)
                                          .select(device.name),
                                    ),
                                  TextButton.icon(
                                    onPressed: audio.changing
                                        ? null
                                        : () => ref
                                              .read(
                                                audioDevicesProvider.notifier,
                                              )
                                              .refresh(),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: Text(
                                      label('刷新设备', 'Refresh devices'),
                                    ),
                                  ),
                                ],
                              ),
                              if (audio.error != null) _ErrorText(audio.error!),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Section(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SectionTitle(
                                title: label('亮度', 'Brightness'),
                                value: level == null
                                    ? '—'
                                    : '${(level * 100).round()} %',
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.brightness_6_rounded),
                                  Expanded(
                                    child: Slider(
                                      min: 0.01,
                                      value: (level ?? 0.72).clamp(0.01, 1.0),
                                      semanticFormatterCallback: (value) =>
                                          '${(value * 100).round()} %',
                                      onChanged: output == null || level == null
                                          ? null
                                          : (value) => ref
                                                .read(
                                                  displayBrightnessProvider
                                                      .notifier,
                                                )
                                                .setLevel(output, value),
                                      onChangeEnd:
                                          output == null || level == null
                                          ? null
                                          : (value) => ref
                                                .read(
                                                  displayBrightnessProvider
                                                      .notifier,
                                                )
                                                .commitLevel(output, value),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Section(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SectionTitle(
                                title: label('快捷操作', 'Quick controls'),
                              ),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns =
                                      (constraints.maxWidth /
                                              (90 *
                                                  MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(1)))
                                          .floor()
                                          .clamp(1, 3);
                                  final tileWidth =
                                      (constraints.maxWidth -
                                          (columns - 1) * 10) /
                                      columns;
                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 12,
                                    children: [
                                      _QuickTile(
                                        width: tileWidth,
                                        icon: Icons.wifi_rounded,
                                        label: 'Wi-Fi',
                                        detailsKey: _wifiDetailsKey,
                                        detailsFocus: _wifiDetailsFocus,
                                        onDetails: () => _showDetail(
                                          ConnectivityMenuKind.wifi,
                                        ),
                                        active:
                                            network.snapshot.wirelessEnabled,
                                        tooltip: network.radioChanging
                                            ? label('正在切换…', 'Changing…')
                                            : label('开关 Wi-Fi', 'Toggle Wi-Fi'),
                                        onPressed: wifiAvailable
                                            ? () => ref
                                                  .read(
                                                    networkConnectivityProvider
                                                        .notifier,
                                                  )
                                                  .toggleWireless()
                                            : null,
                                      ),
                                      _QuickTile(
                                        width: tileWidth,
                                        icon: Icons.bluetooth_rounded,
                                        label: label('蓝牙', 'Bluetooth'),
                                        detailsKey: _bluetoothDetailsKey,
                                        detailsFocus: _bluetoothDetailsFocus,
                                        onDetails: () => _showDetail(
                                          ConnectivityMenuKind.bluetooth,
                                        ),
                                        active: bluetooth.powered,
                                        tooltip: bluetooth.powerChanging
                                            ? label('正在切换…', 'Changing…')
                                            : label('开关蓝牙', 'Toggle Bluetooth'),
                                        onPressed:
                                            bluetooth.available &&
                                                !bluetooth.initializing &&
                                                !bluetooth.powerChanging
                                            ? () => ref
                                                  .read(
                                                    bluetoothProvider.notifier,
                                                  )
                                                  .togglePower()
                                            : null,
                                      ),
                                      _QuickTile(
                                        width: tileWidth,
                                        icon: dark
                                            ? Icons.dark_mode_rounded
                                            : Icons.light_mode_rounded,
                                        label: label('深色外观', 'Dark appearance'),
                                        active: dark,
                                        onPressed: () => ref
                                            .read(
                                              shellSettingsProvider.notifier,
                                            )
                                            .setColorSchemePreference(
                                              dark
                                                  ? DesktopColorSchemePreference
                                                        .preferLight
                                                  : DesktopColorSchemePreference
                                                        .preferDark,
                                            ),
                                      ),
                                      _QuickTile(
                                        width: tileWidth,
                                        icon: Icons.screenshot_monitor_rounded,
                                        label: label('截图', 'Screenshot'),
                                        onPressed: () => closeThen(
                                          ref
                                              .read(
                                                systemActionsServiceProvider,
                                              )
                                              .takeScreenshot,
                                        ),
                                      ),
                                      _QuickTile(
                                        width: tileWidth,
                                        icon: Icons.lock_outline_rounded,
                                        label: label('锁屏', 'Lock'),
                                        onPressed: () => closeThen(
                                          ref
                                              .read(
                                                shellControllerProvider
                                                    .notifier,
                                              )
                                              .lock,
                                        ),
                                      ),
                                      _QuickTile(
                                        width: tileWidth,
                                        icon: Icons.settings_rounded,
                                        label: label('电源设置', 'Power settings'),
                                        onPressed: () => closeThen(
                                          services.openPowerSettings,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              Text(
                                ref.watch(services.connectedWifi)?.ssid ??
                                    label('Wi-Fi 未连接', 'Wi-Fi disconnected'),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              if (network.error != null)
                                _ErrorText(network.error!),
                              if (bluetooth.error != null)
                                _ErrorText(bluetooth.error!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.shellTheme.cardColor(
        context.shellColors.surfaceContainerLow,
      ),
      borderRadius: context.shellTheme.borderRadius(20),
      border: Border.all(color: context.shellColors.hairlineSoft),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.value});
  final String title;
  final String? value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      if (value != null)
        Text(value!, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active,
    this.tooltip,
    this.onDetails,
    this.detailsKey,
    this.detailsFocus,
  });
  final double width;
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool? active;
  final VoidCallback? onPressed;
  final VoidCallback? onDetails;
  final GlobalKey? detailsKey;
  final FocusNode? detailsFocus;

  @override
  Widget build(BuildContext context) {
    final shell = context.shellTheme;
    final radius = shell.borderRadius(active == true ? 16 : 28);
    final background = active == true
        ? shell.accentPalette.container
        : context.shellColors.tileOff;
    final foreground = onPressed == null
        ? context.shellColors.glyphInactive
        : active == true
        ? shell.accentPalette.onContainer
        : context.shellColors.textPrimary;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Material(
            color: background,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 52,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Tooltip(
                      message: tooltip ?? label,
                      child: Semantics(
                        label: label,
                        button: true,
                        enabled: onPressed != null,
                        toggled: active,
                        child: InkWell(
                          onTap: onPressed,
                          borderRadius: radius,
                          child: Center(
                            child: Icon(icon, size: 25, color: foreground),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onDetails != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: IconButton(
                          key: detailsKey,
                          focusNode: detailsFocus,
                          tooltip: zh ? '$label 详细信息' : '$label details',
                          onPressed: onDetails,
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: foreground.withValues(alpha: 0.10),
                            foregroundColor: active == true
                                ? shell.accentPalette.onContainer
                                : context.shellColors.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: shell.borderRadius(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _PanelSimulation extends Simulation {
  _PanelSimulation(this.motion);
  final PanelMotion motion;
  @override
  double x(double time) =>
      motion.isDone(time) ? motion.target : motion.position(time);
  @override
  double dx(double time) => motion.isDone(time) ? 0 : motion.velocity(time);
  @override
  bool isDone(double time) => motion.isDone(time);
}
