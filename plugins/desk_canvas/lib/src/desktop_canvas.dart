// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/surfaces.dart' show ShellSurfacePresentation;
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/services.dart';

import 'desktop_store.dart';
import 'desktop_viewport.dart';
import 'desktop_drag_layout.dart';
import 'interaction_highlight.dart';
import 'desktop_sdk_adapter.dart';

class DesktopCanvas extends ConsumerStatefulWidget {
  const DesktopCanvas({
    required this.services,
    required this.monitorId,
    required this.bounds,
    this.createStore,
    super.key,
  });
  final ShellServices services;
  final int monitorId;
  final Rect bounds;
  final DesktopStore Function(VoidCallback onChanged)? createStore;
  @override
  ConsumerState<DesktopCanvas> createState() => _DesktopCanvasState();
}

class _DesktopCanvasState extends ConsumerState<DesktopCanvas> {
  late final DesktopStore store;
  final focus = FocusNode(debugLabel: 'Desk Canvas');
  final selected = <String>{};
  Map<String, GridSlot> layout = {};
  Offset? selectionStart;
  final selectionRectangle = ValueNotifier<Rect?>(null);
  int feedbackEpoch = 0;
  int interactionGeneration = 0;
  int? closingPopupId;
  Offset? menuPosition;
  DesktopItem? menuItem;
  String? dialogTitle, message;
  final text = TextEditingController();
  Future<void> Function(String)? submit;
  bool busy = false;
  int dialogGeneration = 0;
  final dragMotion = ValueNotifier(Offset.zero);
  Offset get dragOffset => dragMotion.value;
  String? dragKey;
  Size area = Size.zero;
  bool layoutDirty = true;
  late DesktopViewportIndex viewportIndex;
  List<DesktopItem>? layoutItems;
  double layoutIconSize = 0;
  final icons = <String, String?>{};
  final pendingIcons = <String>{};
  final tileContents =
      <
        String,
        ({
          DesktopItem item,
          String? icon,
          ShellThemeData theme,
          double size,
          Widget child,
        })
      >{};
  final scroll = ScrollController();
  final popupRevision = ValueNotifier(0);
  ShellPopupHandle? popup;
  ShellPopupController? popupController;
  bool popupScheduled = false;
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (popup != null || menuPosition != null || dialogTitle != null) {
      popupRevision.value++;
    }
  }

  void syncPopup() {
    if (popupScheduled) return;
    popupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      popupScheduled = false;
      if (!mounted) return;
      if (menuPosition == null && dialogTitle == null) {
        if (popup != null) setState(resetFeedback);
        closePopup();
        return;
      }
      if (!ShellSurfacePresentation.visibleOf(context)) {
        menuPosition = null;
        dialogTitle = null;
        closePopup();
        return;
      }
      final active = popup;
      if (active != null) {
        final closing = ref
            .read(shellPopupControllerProvider)
            .any((entry) => entry.id == active.id && entry.closing);
        // A menu reopened during a close animation replaces that surface at
        // once instead of waiting for the previous transition to finish.
        if (!closing) return;
        popupController!.completeClose(active.id);
        popup = null;
      }
      popupController = ref.read(shellPopupControllerProvider.notifier);
      final closingId = closingPopupId;
      closingPopupId = null;
      if (closingId != null) popupController!.completeClose(closingId);
      popup = popupController!.show(
        debugLabel: 'Desk Canvas menu',
        // A desktop context menu must never dim the wallpaper behind it.
        barrierColor: Colors.transparent,
        dismissPolicy: ShellDismissPolicy.none,
        // No fade: a managed surface fades through an Opacity layer, and a
        // BackdropFilter inside that layer loses the scene behind it, so the
        // panel looked transparent first and only became blurred once the
        // layer was gone. Windows 10 context menus appear instantly anyway.
        transitionDuration: Duration.zero,
        builder: (context, _) => ValueListenableBuilder(
          valueListenable: popupRevision,
          builder: (context, revision, child) {
            final theme = ShellTheme.of(context);
            return Theme(
              data: materialTheme(theme),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      dismissPopup,
                },
                child: Focus(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: dismissPopup,
                          onSecondaryTapDown: (details) {
                            if (dialogTitle != null) return;
                            openMenuAt(
                              details.globalPosition - widget.bounds.topLeft,
                              null,
                            );
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: widget.bounds,
                        child: Stack(
                          children: [
                            if (menuPosition != null) menu(theme),
                            if (dialogTitle != null) dialog(theme),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }

  /// Material roles for menus and dialogs, derived from the shell text theme so
  /// labels inherit the user's font and the SDK's CJK fallbacks instead of the
  /// bundled Material default.
  ShellThemeData? _materialSource;
  ThemeData? _materialCache;
  ThemeData materialTheme(ShellThemeData theme) {
    if (identical(_materialSource, theme) && _materialCache != null) {
      return _materialCache!;
    }
    _materialSource = theme;
    final base = theme.toMaterialTheme();
    TextStyle style(double size, FontWeight weight, Color color) =>
        theme.text.base.copyWith(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.3,
        );
    final text = TextTheme(
      titleMedium: style(17, FontWeight.w600, theme.colors.textPrimary),
      bodyLarge: style(14, FontWeight.w400, theme.colors.textPrimary),
      bodyMedium: style(13, FontWeight.w400, theme.colors.textPrimary),
      bodySmall: style(12, FontWeight.w400, theme.colors.textSecondary),
      labelLarge: style(14, FontWeight.w500, theme.colors.textPrimary),
      labelMedium: style(12, FontWeight.w500, theme.colors.textSecondary),
      labelSmall: style(11, FontWeight.w400, theme.colors.textTertiary),
    );
    return _materialCache = base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
    );
  }

  void closePopup({bool immediate = false}) {
    final active = popup;
    popup = null;
    if (immediate) {
      final closingId = closingPopupId;
      closingPopupId = null;
      if (closingId != null && closingId != active?.id) {
        popupController?.completeClose(closingId);
      }
    }
    if (active != null) {
      if (immediate) {
        popupController?.completeClose(active.id);
      } else {
        closingPopupId = active.id;
        active.close();
      }
    }
  }

  void dismissPopup() {
    if (busy && dialogTitle != null) return;
    setState(() {
      menuPosition = null;
      dialogTitle = null;
      submit = null;
      dialogGeneration++;
      resetFeedback();
    });
    focus.requestFocus();
  }

  void openMenuAt(Offset position, DesktopItem? item) {
    interactionGeneration++;
    if (busy && dialogTitle != null) return;
    setState(() {
      dialogTitle = null;
      submit = null;
      menuItem = item;
      menuPosition = position;
      feedbackEpoch++;
    });
  }

  List<DesktopApp> get installedApps =>
      ref
          .read(homeGridControllerProvider)
          .value
          ?.slots
          .whereType<HomeGridItem>()
          .map((i) => i.app)
          .whereType<DesktopApp>()
          .toList() ??
      [];
  void resolveIcons() {
    final missing = store.items
        .map((i) => i.entry?.fields['Icon'])
        .whereType<String>()
        .where(
          (icon) => !icons.containsKey(icon) && !pendingIcons.contains(icon),
        )
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    pendingIcons.addAll(missing);
    unawaited(
      resolveDesktopIcons(missing)
          .then((resolved) {
            if (mounted) setState(() => icons.addAll(resolved));
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() {
                for (final icon in missing) {
                  icons[icon] = null;
                }
              });
            }
          })
          .whenComplete(() => pendingIcons.removeAll(missing)),
    );
  }

  double get cellWidth => store.iconSize + 52;
  double get cellHeight => store.iconSize + 50;
  int get rows => math.max(1, (area.height / cellHeight).floor());
  int get columns => math.max(1, (area.width / cellWidth).floor());
  bool get multiple =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isShiftPressed;
  @override
  void initState() {
    super.initState();
    void changed() {
      if (mounted) {
        if (!identical(layoutItems, store.items)) {
          layoutDirty = true;
          final keys = store.items.map((i) => i.key).toSet();
          tileContents.removeWhere((key, _) => !keys.contains(key));
          selected.removeWhere((key) => !keys.contains(key));
          resolveIcons();
        }
        setState(() {});
      }
    }

    store =
        widget.createStore?.call(changed) ?? DesktopStore(onChanged: changed);
    unawaited(store.start());
  }

  @override
  void dispose() {
    unawaited(store.dispose());
    if (popup case final active?) popupController?.completeClose(active.id);
    popup = null;
    popupRevision.dispose();
    focus.dispose();
    text.dispose();
    scroll.dispose();
    dragMotion.dispose();
    selectionRectangle.dispose();
    final closingId = closingPopupId;
    if (closingId != null) popupController?.completeClose(closingId);
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void resetFeedback() {
    selected.clear();
    feedbackEpoch++;
    dragKey = null;
    dragMotion.value = Offset.zero;
    finishSelection();
  }

  void finishSelection() {
    selectionStart = null;
    selectionRectangle.value = null;
  }

  void choose(DesktopItem item) {
    interactionGeneration++;
    focus.requestFocus();
    setState(() {
      menuPosition = null;
      if (multiple) {
        if (!selected.add(item.key)) selected.remove(item.key);
      } else {
        selected
          ..clear()
          ..add(item.key);
      }
    });
  }

  void open(DesktopItem item) {
    if (busy) return;
    if (item.problem != null) {
      setState(() => message = item.problem);
      return;
    }
    setState(() {
      menuPosition = null;
      resetFeedback();
    });
    closePopup(immediate: true);
    focus.unfocus();
    unawaited(
      perform(() async {
        await store.validateItem(item);
        if (!item.shortcut) {
          await store.actions.open(item);
          return;
        }
        final app = await installedEntry(item, installedApps);
        if (!mounted) return;
        if (app != null) {
          if (item.entry?.fields['DBusActivatable'] == 'true' ||
              item.entry?.fields['Terminal'] == 'true') {
            await store.actions.open(item);
            if (!mounted) return;
            ref
                .read(applicationRecentsProvider.notifier)
                .record(desktopApplicationRecentId(app.id));
          } else if (!await widget.services.launchApplication(
            desktopApplicationRecentId(app.id),
            monitorId: widget.monitorId,
          )) {
            throw const FileSystemException('宿主无法启动该应用');
          }
        } else {
          setState(() {
            dialogTitle = '运行应用快捷方式？';
            message = null;
            submit = (_) async {
              await store.validateItem(item);
              await store.actions.open(item);
            };
            text.text = '';
          });
        }
      }),
    );
  }

  void nameDialog(
    String title,
    String initial,
    Future<void> Function(String) action,
  ) {
    if (busy) return;
    dialogGeneration++;
    setState(() {
      menuPosition = null;
      dialogTitle = title;
      text.text = initial;
      submit = action;
    });
  }

  List<DesktopItem> get selectedItems =>
      store.items.where((i) => selected.contains(i.key)).toList();
  void trash() {
    if (busy) return;
    final items = selectedItems;
    if (items.isEmpty) return;
    setState(() {
      menuPosition = null;
      dialogTitle = '将 ${items.length} 个项目移入回收站？';
      text.text = '';
      submit = (_) async {
        for (final item in items) {
          await store.validateItem(item);
          await store.actions.trash(item);
        }
        await store.refresh();
      };
    });
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    interactionGeneration++;
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.escape &&
        (menuPosition != null || dialogTitle != null)) {
      if (!busy) {
        setState(() {
          menuPosition = null;
          dialogTitle = null;
          submit = null;
        });
      }
      return KeyEventResult.handled;
    }
    if (dialogTitle != null) return KeyEventResult.ignored;
    if (logical == LogicalKeyboardKey.escape) {
      setState(() => selected.clear());
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isControlPressed) {
      setState(() => selected.addAll(store.items.map((i) => i.key)));
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.f5) {
      unawaited(store.refresh());
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.enter && selectedItems.length == 1) {
      open(selectedItems.single);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.delete) {
      trash();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.f2 && selectedItems.length == 1) {
      final item = selectedItems.single;
      nameDialog('重命名', item.key, (name) => store.rename(item, name));
      return KeyEventResult.handled;
    }
    final delta = {
      LogicalKeyboardKey.arrowDown: 1,
      LogicalKeyboardKey.arrowUp: -1,
      LogicalKeyboardKey.arrowRight: rows,
      LogicalKeyboardKey.arrowLeft: -rows,
    }[logical];
    if (delta != null && store.items.isNotEmpty) {
      final ordered = store.items.toList()
        ..sort((a, b) {
          final x = layout[a.key]!;
          final y = layout[b.key]!;
          return (x.column * rows + x.row).compareTo(y.column * rows + y.row);
        });
      final current = ordered.indexWhere((i) => selected.contains(i.key));
      final next = ordered[(current + delta).clamp(0, ordered.length - 1)];
      setState(() {
        if (!multiple) selected.clear();
        selected.add(next.key);
      });
      if (scroll.hasClients) {
        final rect = itemRect(next.key);
        final currentOffset = scroll.offset;
        if (rect.left < currentOffset) {
          scroll.jumpTo(rect.left.clamp(0, scroll.position.maxScrollExtent));
        } else if (rect.right > currentOffset + area.width) {
          scroll.jumpTo(
            (rect.right - area.width).clamp(0, scroll.position.maxScrollExtent),
          );
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Rect itemRect(String key) {
    final slot = layout[key]!;
    return Rect.fromLTWH(
      slot.column * cellWidth,
      slot.row * cellHeight,
      cellWidth,
      cellHeight,
    );
  }

  void drop(DesktopItem item, Offset delta) {
    // Sub-cell gestures must not snap overflow items back into visible columns.
    if ((delta.dx / cellWidth).round() == 0 &&
        (delta.dy / cellHeight).round() == 0) {
      return;
    }
    final keys = selected.contains(item.key) ? selected.toList() : [item.key];
    final dx = (delta.dx / cellWidth).round(),
        dy = (delta.dy / cellHeight).round();
    store.positions.addAll(
      moveDesktopItems(layout, keys, dx, dy, columns, rows),
    );
    layoutDirty = true;
    setState(() {});
    unawaited(perform(store.save));
  }

  /// Windows 10 shortcut badge: a small white square with a dark arrow.
  Widget shortcutBadge() => Container(
    width: 13,
    height: 13,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(2),
      border: Border.all(
        color: Colors.black.withValues(alpha: 0.3),
        width: 0.6,
      ),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
      ],
    ),
    child: const Icon(Icons.shortcut, size: 9, color: Color(0xFF1B1B1F)),
  );

  Widget tile(DesktopItem item, ShellThemeData theme) {
    final rect = itemRect(item.key);
    final isSelected = selected.contains(item.key);
    return Positioned.fromRect(
      key: ValueKey(item.key),
      rect: rect,
      child: RetainedTranslation(
        translation: dragKey != null && isSelected
            ? dragMotion
            : const AlwaysStoppedAnimation(Offset.zero),
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kPrimaryMouseButton) choose(item);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => open(item),
            onSecondaryTapDown: (details) {
              interactionGeneration++;
              focus.requestFocus();
              setState(() {
                if (!isSelected) {
                  selected
                    ..clear()
                    ..add(item.key);
                }
                menuItem = item;
                feedbackEpoch++;
                menuPosition =
                    rect.topLeft +
                    details.localPosition -
                    Offset(scroll.hasClients ? scroll.offset : 0.0, 0);
              });
            },
            onPanStart: (_) {
              interactionGeneration++;
              setState(() {
                dragKey = item.key;
                dragMotion.value = Offset.zero;
              });
            },
            onPanUpdate: (details) {
              if (dragKey != item.key) return;
              dragMotion.value += details.delta;
            },
            onPanEnd: (_) {
              if (dragKey != item.key) return;
              final delta = dragOffset;
              setState(() {
                dragKey = null;
                dragMotion.value = Offset.zero;
              });
              drop(item, delta);
            },
            onPanCancel: () {
              if (dragKey != item.key) return;
              setState(() {
                dragKey = null;
                dragMotion.value = Offset.zero;
              });
            },
            child: Semantics(
              label: item.name,
              selected: isSelected,
              button: true,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DesktopHighlight(
                  theme: theme,
                  selected: isSelected,
                  feedbackEpoch: feedbackEpoch,
                  hoverEnabled:
                      menuPosition == null && dialogTitle == null && !busy,
                  child: tileContent(item, theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget tileContent(DesktopItem item, ShellThemeData theme) {
    final iconPath = icons[item.entry?.fields['Icon']];
    final cached = tileContents[item.key];
    if (cached != null &&
        identical(cached.item, item) &&
        cached.icon == iconPath &&
        identical(cached.theme, theme) &&
        cached.size == store.iconSize) {
      return cached.child;
    }
    final child = buildTileContent(item, iconPath, theme);
    tileContents[item.key] = (
      item: item,
      icon: iconPath,
      theme: theme,
      size: store.iconSize,
      child: child,
    );
    return child;
  }

  Widget buildTileContent(
    DesktopItem item,
    String? iconPath,
    ShellThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Column(
        children: [
          SizedBox(
            width: store.iconSize,
            height: store.iconSize,
            child: item.shortcut
                ? Stack(
                    children: [
                      Positioned.fill(child: AppIconImage(iconPath: iconPath)),
                      Positioned(bottom: 0, left: 0, child: shortcutBadge()),
                    ],
                  )
                : Icon(
                    item.directory ? Icons.folder : Icons.insert_drive_file,
                    size: store.iconSize,
                    color: item.directory
                        ? theme.accentPalette.primary
                        : theme.colors.textPrimary,
                  ),
          ),
          const SizedBox(height: 4),
          // Windows 10 desktop labels sit directly on the wallpaper:
          // white text with a soft dark shadow, no backing plate.
          Expanded(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.text.base.copyWith(
                fontSize: 12.5,
                height: 1.15,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.85),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget panel(
    ShellThemeData theme, {
    required Widget child,
    double radius = 8,
  }) {
    return ShellBackdropBlur(
      borderRadius: theme.borderRadius(radius),
      separateChild: true,
      blur: theme.effectivePanelOpacity < 1,
      child: Material(
        color: theme.panelColor(theme.colors.surfaceContainer),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: theme.borderRadius(radius),
          side: BorderSide(color: theme.colors.hairlineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  /// Dense Windows 10 menu row: 30px high, 13px label, 15px leading icon.
  Widget menuButton(
    ShellThemeData theme,
    String label,
    VoidCallback? action, {
    IconData? icon,
    bool checked = false,
    bool autofocus = false,
  }) {
    return TextButton(
      autofocus: autofocus,
      onPressed: busy ? null : action,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        foregroundColor: theme.colors.textPrimary,
        disabledForegroundColor: theme.colors.textTertiary,
        iconColor: theme.colors.textSecondary,
        disabledIconColor: theme.colors.textTertiary,
        overlayColor: theme.accentPalette.subtle,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashFactory: NoSplash.splashFactory,
        shape: RoundedRectangleBorder(borderRadius: theme.borderRadius(4)),
        textStyle: theme.text.base.copyWith(fontSize: 13, height: 1.2),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: icon == null ? null : Icon(icon, size: 15),
          ),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (checked)
            Icon(Icons.check, size: 15, color: theme.accentPalette.primary),
        ],
      ),
    );
  }

  Widget menuDivider(ShellThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Divider(height: 1, thickness: 1, color: theme.colors.hairlineSoft),
  );

  Widget iconSizeRow(ShellThemeData theme) {
    Widget chip(String label, double size) {
      final active = store.iconSize == size;
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: TextButton(
          onPressed: busy
              ? null
              : () {
                  store.iconSize = size;
                  layoutDirty = true;
                  setState(() => menuPosition = null);
                  unawaited(perform(store.save));
                },
          style: TextButton.styleFrom(
            minimumSize: const Size(28, 24),
            maximumSize: const Size(34, 24),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            splashFactory: NoSplash.splashFactory,
            foregroundColor: active
                ? theme.accentPalette.primary
                : theme.colors.textSecondary,
            backgroundColor: active ? theme.accentPalette.subtle : null,
            shape: RoundedRectangleBorder(borderRadius: theme.borderRadius(4)),
            textStyle: theme.text.base.copyWith(fontSize: 12, height: 1.1),
          ),
          child: Text(label),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 4, 1),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Icon(
              Icons.grid_view_rounded,
              size: 15,
              color: theme.colors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              '图标大小',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.base.copyWith(
                fontSize: 13,
                height: 1.2,
                color: theme.colors.textPrimary,
              ),
            ),
          ),
          chip('小', 32),
          chip('中', 48),
          chip('大', 64),
        ],
      ),
    );
  }

  Widget menu(ShellThemeData theme) {
    const width = 232.0;
    final maxHeight = math.min(
      math.max(120.0, area.height - 16),
      menuItem == null ? 320.0 : 250.0,
    );
    final position = Offset(
      menuPosition!.dx.clamp(8, math.max(8, area.width - width - 8)).toDouble(),
      menuPosition!.dy
          .clamp(8, math.max(8, area.height - maxHeight - 8))
          .toDouble(),
    );
    final item = menuItem;
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: math.max(0.0, math.min(width, area.width - 16)),
      child: ShellInputRegion(
        debugLabel: 'Desk Canvas context menu',
        child: panel(
          theme,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(40, maxHeight)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (item != null) ...[
                      menuButton(
                        theme,
                        '打开',
                        () {
                          setState(() => menuPosition = null);
                          open(item);
                        },
                        icon: Icons.open_in_new,
                        autofocus: true,
                      ),
                      if (selected.length == 1)
                        menuButton(
                          theme,
                          '重命名',
                          () => nameDialog(
                            '重命名',
                            item.key,
                            (name) => store.rename(item, name),
                          ),
                          icon: Icons.drive_file_rename_outline,
                        ),
                      menuButton(
                        theme,
                        selected.length > 1
                            ? '将 ${selected.length} 个项目移入回收站'
                            : '移入回收站',
                        trash,
                        icon: Icons.delete_outline,
                      ),
                      menuDivider(theme),
                      menuButton(theme, '属性', () {
                        setState(() {
                          menuPosition = null;
                          message =
                              '${item.name}\n${item.path}${item.problem == null ? '' : '\n${item.problem}'}';
                        });
                      }, icon: Icons.info_outline),
                    ] else ...[
                      menuButton(
                        theme,
                        '新建文件夹',
                        () => nameDialog('新建文件夹', '新建文件夹', store.createFolder),
                        icon: Icons.create_new_folder_outlined,
                        autofocus: true,
                      ),
                      menuButton(theme, '打开桌面文件夹', () {
                        setState(() => menuPosition = null);
                        if (store.directory case final dir?) {
                          unawaited(
                            perform(
                              () => store.actions.open(
                                DesktopItem(
                                  path: dir,
                                  name: '桌面',
                                  directory: true,
                                ),
                              ),
                            ),
                          );
                        }
                      }, icon: Icons.folder_open_outlined),
                      menuDivider(theme),
                      menuButton(theme, '刷新', () {
                        setState(() => menuPosition = null);
                        unawaited(store.refresh());
                      }, icon: Icons.refresh),
                      menuButton(theme, '按名称整理图标', () {
                        store.positions.clear();
                        layoutDirty = true;
                        setState(() => menuPosition = null);
                        unawaited(perform(store.save));
                      }, icon: Icons.sort_by_alpha),
                      menuButton(
                        theme,
                        store.showHidden ? '隐藏隐藏文件' : '显示隐藏文件',
                        () {
                          store.showHidden = !store.showHidden;
                          setState(() => menuPosition = null);
                          unawaited(
                            perform(() async {
                              await store.save();
                              await store.refresh();
                            }),
                          );
                        },
                        icon: store.showHidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        checked: store.showHidden,
                      ),
                      menuDivider(theme),
                      iconSizeRow(theme),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget dialog(ShellThemeData theme) => Positioned.fill(
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: busy ? null : dismissPopup,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
          ),
        ),
        Center(
          child: ShellInputRegion(
            debugLabel: 'Desk Canvas dialog',
            keyboardPolicy: ShellKeyboardPolicy.capture,
            child: panel(
              theme,
              radius: 14,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(420, math.max(0, area.width - 24)),
                  maxHeight: math.max(0, area.height - 24),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          dialogTitle!,
                          style: theme.text.base.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: theme.colors.textPrimary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (dialogTitle == '新建文件夹' || dialogTitle == '重命名')
                          TextField(
                            controller: text,
                            autofocus: true,
                            onSubmitted: (_) => finishDialog(),
                            style: theme.text.base.copyWith(
                              fontSize: 14,
                              color: theme.colors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: theme.borderRadius(4),
                              ),
                            ),
                          )
                        else
                          Text(
                            dialogTitle!.startsWith('运行')
                                ? '仅运行你信任的快捷方式。此文件可以启动程序。'
                                : '真实文件将进入系统回收站；不会卸载应用。',
                            style: theme.text.base.copyWith(
                              fontSize: 13,
                              color: theme.colors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: busy ? null : dismissPopup,
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              autofocus:
                                  dialogTitle != '新建文件夹' &&
                                  dialogTitle != '重命名',
                              onPressed: busy ? null : finishDialog,
                              child: Text(busy ? '处理中…' : '确认'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  void finishDialog() {
    final action = submit;
    if (action == null || busy) return;
    final value = text.text;
    final generation = ++dialogGeneration;
    final launching = dialogTitle?.startsWith('运行') ?? false;
    if (launching) {
      // Release the popup's restore-focus request before dispatching the
      // application, so a late close cannot focus the desktop over its window.
      setState(() {
        dialogTitle = null;
        submit = null;
        resetFeedback();
      });
      closePopup(immediate: true);
      focus.unfocus();
    }
    unawaited(
      perform(() async {
        await action(value);
        if (mounted && generation == dialogGeneration) {
          setState(() {
            dialogTitle = null;
            submit = null;
            resetFeedback();
          });
          if (!launching) focus.requestFocus();
        }
      }),
    );
  }

  Widget background({bool scrolled = false}) => Positioned.fill(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        interactionGeneration++;
        focus.requestFocus();
        setState(() {
          selected.clear();
          menuPosition = null;
        });
      },
      onSecondaryTapDown: (details) {
        interactionGeneration++;
        focus.requestFocus();
        setState(() {
          menuItem = null;
          menuPosition =
              (details.localPosition -
              Offset(scrolled && scroll.hasClients ? scroll.offset : 0.0, 0));
        });
      },
      onPanStart: (details) {
        interactionGeneration++;
        focus.requestFocus();
        final start =
            details.localPosition -
            Offset(scrolled && scroll.hasClients ? scroll.offset : 0.0, 0);
        selectionStart = start;
        selectionRectangle.value = Rect.fromPoints(start, start);
        if (!multiple && selected.isNotEmpty) setState(() => selected.clear());
      },
      onPanUpdate: (details) {
        final start = selectionStart;
        if (start == null) return;
        final end =
            details.localPosition -
            Offset(scrolled && scroll.hasClients ? scroll.offset : 0.0, 0);
        final rectangle = Rect.fromPoints(start, end);
        selectionRectangle.value = rectangle;
        final content = rectangle.shift(
          Offset(scroll.hasClients ? scroll.offset : 0.0, 0),
        );
        final candidates = viewportIndex.visible(
          content.left,
          math.max(content.width, 0.001),
          cellWidth,
        );
        final next = <String>{
          if (multiple) ...selected,
          for (final item in candidates)
            if (content.overlaps(itemRect(item.key))) item.key,
        };
        if (!setEquals(selected, next)) {
          setState(() {
            selected
              ..clear()
              ..addAll(next);
          });
        }
      },
      onPanEnd: (_) => finishSelection(),
      onPanCancel: finishSelection,
      child: const SizedBox.expand(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(shellPopupControllerProvider, (_, next) {
      final active = popup;
      if (active != null &&
          !next.any((entry) => entry.id == active.id && !entry.closing)) {
        closingPopupId = active.id;
        popup = null;
        final feedback = feedbackEpoch;
        final generation = dialogGeneration;
        final oldMenu = menuPosition;
        final oldDialog = dialogTitle;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              popup == null &&
              feedback == feedbackEpoch &&
              generation == dialogGeneration &&
              menuPosition == oldMenu &&
              dialogTitle == oldDialog) {
            setState(() {
              menuPosition = null;
              dialogTitle = null;
              submit = null;
              dialogGeneration++;
              resetFeedback();
            });
          }
        });
      }
    });
    ref.listen(
      widget.services
          .windows(widget.monitorId)
          .select(
            (windows) => windows
                .where((window) => window.active)
                .map((window) => window.id)
                .firstOrNull,
          ),
      (previous, next) {
        if (next == null || next == previous) return;
        final generation = interactionGeneration;
        final feedback = feedbackEpoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              interactionGeneration != generation ||
              feedbackEpoch != feedback) {
            return;
          }
          final active = ref
              .read(widget.services.windows(widget.monitorId))
              .where((window) => window.active)
              .map((window) => window.id)
              .firstOrNull;
          if (active == next) setState(resetFeedback);
        });
      },
    );
    final visible = ShellSurfacePresentation.visibleOf(context);
    if (!visible) finishSelection();
    if (!visible && (menuPosition != null || dialogTitle != null)) {
      menuPosition = null;
      dialogTitle = null;
      dialogGeneration++;
    }
    if (popup != null || menuPosition != null || dialogTitle != null) {
      syncPopup();
    }
    final theme = ShellTheme.of(context);
    return Theme(
      data: materialTheme(theme),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (area != constraints.biggest || layoutIconSize != store.iconSize) {
            layoutDirty = true;
          }
          area = constraints.biggest;
          layoutIconSize = store.iconSize;
          if (layoutDirty) {
            layoutDirty = false;
            layout = arrange(
              store.items.map((i) => i.key).toList(),
              store.positions,
              columns,
              rows,
            );
            viewportIndex = DesktopViewportIndex(store.items, layout);
            layoutItems = store.items;
            final changed = layout.entries.any(
              (entry) => store.positions[entry.key] != entry.value,
            );
            if (changed) {
              store.positions.addAll(layout);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  unawaited(
                    store.save().catchError((Object e) {
                      if (mounted) setState(() => message = '布局保存失败：$e');
                    }),
                  );
                }
              });
            }
          }
          final extraColumns = viewportIndex.columnCount;
          return Focus(
            focusNode: focus,
            onKeyEvent: key,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (extraColumns <= columns) background(),
                if (store.loading)
                  Positioned(
                    left: 16,
                    top: 16,
                    child: Material(
                      color: theme.panelColor(theme.colors.surfaceContainer),
                      shape: RoundedRectangleBorder(
                        borderRadius: theme.borderRadius(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          '正在读取桌面…',
                          style: theme.text.base.copyWith(
                            fontSize: 12,
                            color: theme.colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (store.error case final error?)
                  Positioned(
                    left: 16,
                    top: 16,
                    right: 16,
                    child: Material(
                      color: theme.panelColor(
                        theme.colors.surfaceContainerHigh,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: theme.borderRadius(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                error,
                                style: theme.text.base.copyWith(
                                  fontSize: 13,
                                  color: theme.colors.textPrimary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => unawaited(store.refresh()),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (extraColumns <= columns)
                  ...store.items.map((i) => tile(i, theme))
                else
                  Positioned.fill(
                    child: SingleChildScrollView(
                      controller: scroll,
                      scrollDirection: Axis.horizontal,
                      child: AnimatedBuilder(
                        animation: scroll,
                        builder: (context, _) {
                          final offset = scroll.hasClients
                              ? scroll.offset
                              : 0.0;
                          final visibleItems = viewportIndex.visible(
                            offset,
                            area.width,
                            cellWidth,
                            pinned: dragKey == null ? const {} : selected,
                          );
                          return SizedBox(
                            width: extraColumns * cellWidth,
                            height: area.height,
                            child: Stack(
                              children: [
                                background(scrolled: true),
                                for (final item in visibleItems)
                                  tile(item, theme),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _SelectionPainter(selectionRectangle, theme),
                      ),
                    ),
                  ),
                ),
                if (message case final value?)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    right: 16,
                    child: Material(
                      color: theme.panelColor(
                        theme.colors.surfaceContainerHigh,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: theme.borderRadius(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                value,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: theme.text.base.copyWith(
                                  fontSize: 13,
                                  color: theme.colors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => message = null),
                              iconSize: 18,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The marquee is paint-only; unchanged selection no longer rebuilds all icons.
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.rectangle, this.theme) : super(repaint: rectangle);
  final ValueNotifier<Rect?> rectangle;
  final ShellThemeData theme;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = rectangle.value;
    if (rect == null || rect.isEmpty) return;
    final painter = BoxDecoration(
      color: theme.accentPalette.primary.withValues(alpha: 0.16),
      border: Border.all(color: theme.accentPalette.primary),
      borderRadius: theme.borderRadius(2),
    ).createBoxPainter();
    try {
      painter.paint(canvas, rect.topLeft, ImageConfiguration(size: rect.size));
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.rectangle != rectangle ||
      !identical(oldDelegate.theme, theme);
  @override
  bool shouldRebuildSemantics(_SelectionPainter oldDelegate) => false;
}
