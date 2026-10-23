// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'launcher_logic.dart';
import 'shortcut_writer.dart';
import 'interaction_highlight.dart';
import 'smooth_scroll.dart';
import 'entry_retention.dart';
import 'retained_launcher_entry.dart';

/// Windows 10 Start structure, painted with Denial theme roles.
class AppShelfView extends ConsumerStatefulWidget {
  const AppShelfView({required this.launcher, super.key});
  final LauncherContext launcher;
  @override
  ConsumerState<AppShelfView> createState() => _AppShelfViewState();
}

class _AppShelfViewState extends ConsumerState<AppShelfView> {
  static const double _rowExtent = 36;
  static const double _menuWidth = 240;
  static const double _menuRowExtent = 36;
  static const double _menuSubtitleExtent = 46;

  final _search = TextEditingController();
  late final _scroll = _createScrollController();
  late final _tileScroll = _createScrollController();
  LauncherScrollController _createScrollController() =>
      LauncherScrollController(
        motionScale: () =>
            ref.read(shellSettingsProvider).animations.durationScale,
        animationsDisabled: () => MediaQuery.disableAnimationsOf(context),
      );
  final _writer = ShortcutWriter();
  final _rowRetention = EntryRetention(96);
  final _tileRetention = EntryRetention(12);
  final _menuFocus = FocusNode(debugLabel: 'App Shelf menu');
  final _gridFocus = FocusNode(debugLabel: 'App Shelf list');
  final _listAnchor = GlobalKey(debugLabel: 'App Shelf rows');
  String? _menuId;
  bool _menuCanSend = false;
  Offset _menuPosition = Offset.zero;
  String? _notice;
  Timer? _noticeTimer;
  bool _busy = false;
  int _selected = 0;
  int _menuChoice = 0;
  int _generation = 0;
  LauncherContext get launcher => widget.launcher;
  bool get chinese => Localizations.localeOf(context).languageCode == 'zh';
  String tr(String zh, String en) => chinese ? zh : en;

  @override
  void didUpdateWidget(covariant AppShelfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launcher.visible != launcher.visible) {
      _generation++;
      _menuId = null;
      _notice = null;
      _noticeTimer?.cancel();
      _selected = 0;
      if (!launcher.visible) {
        _scroll.stop();
        _tileScroll.stop();
      }
      if (launcher.visible) {
        _search.clear();
        _resetScroll();
      }
    }
  }

  void _resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && launcher.visible && _scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _noticeTimer?.cancel();
    _search.dispose();
    _scroll.dispose();
    _tileScroll.dispose();
    _menuFocus.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  ApplicationIndex<LauncherApplication>? _index;
  ApplicationCatalog<LauncherApplication>? _preparedCatalog;
  List<LauncherApplication>? _catalog;
  List<String>? _recents;
  String? _query;
  ApplicationIndex<LauncherApplication> get _applicationIndex {
    if (!identical(_catalog, launcher.applications) ||
        _preparedCatalog == null) {
      _catalog = launcher.applications;
      _preparedCatalog = ApplicationCatalog(
        launcher.applications,
        (a) => a.id,
        (a) => a.name,
        (a) => a.searchableText,
      );
      _index = null;
    }
    if (_index == null ||
        !identical(_recents, launcher.recentApplicationIds) ||
        _query != _search.text) {
      _recents = launcher.recentApplicationIds;
      _query = _search.text;
      _index = _preparedCatalog!.query(
        launcher.recentApplicationIds,
        _search.text,
      );
    }
    return _index!;
  }

  List<LauncherApplication> get _apps => _applicationIndex.applications;

  String? _source(String id) {
    final state = ref.read(homeGridControllerProvider).asData?.value;
    if (state == null) return null;
    for (final slot in state.slots) {
      final app = slot?.app;
      if (app != null && desktopApplicationRecentId(app.id) == id) {
        return app.desktopPath;
      }
    }
    return null;
  }

  LauncherApplication? _appById(String? id) {
    if (id == null) return null;
    for (final app in _apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  void _showNotice(String value) {
    _noticeTimer?.cancel();
    setState(() => _notice = value);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _notice == value) setState(() => _notice = null);
    });
  }

  void _closeMenu({bool restoreSearch = true}) {
    if (_menuId == null) return;
    setState(() => _menuId = null);
    if (restoreSearch) launcher.searchFocusNode.requestFocus();
  }

  void _openMenu(String id, Offset globalPosition) {
    if (!launcher.visible) return;
    final box = context.findRenderObject() as RenderBox?;
    _openMenuAt(id, box?.globalToLocal(globalPosition) ?? globalPosition);
  }

  void _openMenuAt(String id, Offset local) {
    _scroll.stop();
    _tileScroll.stop();
    setState(() {
      _menuId = id;
      _menuChoice = 0;
      _menuCanSend = _source(id) != null;
      _menuPosition = local;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menuId == id) _menuFocus.requestFocus();
    });
  }

  void _launch(String id) {
    if (!launcher.visible) return;
    setState(() => _menuId = null);
    launcher.onLaunch(id);
  }

  Future<void> _send(String id) async {
    final source = _source(id);
    if (source == null || _busy || !launcher.visible) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _menuId = null;
    });
    _showNotice(tr('正在创建快捷方式…', 'Creating shortcut…'));
    launcher.searchFocusNode.requestFocus();
    try {
      final result = await _writer.send(source);
      if (!mounted || generation != _generation || !launcher.visible) return;
      _showNotice(switch (result.status) {
        ShortcutStatus.created => tr('已发送到桌面', 'Sent to desktop'),
        ShortcutStatus.alreadyExists => tr(
          '桌面上已有相同快捷方式',
          'This shortcut is already on the desktop',
        ),
        ShortcutStatus.conflict => tr(
          '桌面已有同名文件。请先移走或重命名该文件，再重试。',
          'A different file already uses this name. Move or rename it before retrying.',
        ),
      });
    } on Object catch (error) {
      if (mounted && generation == _generation && launcher.visible) {
        _showNotice('${tr('创建失败', 'Could not create shortcut')}: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _ensureVisible(int index, int count) {
    if (!_scroll.hasClients || count == 0) return;
    final target = revealSelection(
      _applicationIndex.applicationRows[index.clamp(0, count - 1)],
      1,
      _rowExtent,
      _scroll.destination,
      _scroll.position.viewportDimension,
      _scroll.position.maxScrollExtent,
    );
    if (target != null) _scroll.reveal(target);
  }

  void _moveTo(int index, int count) {
    if (count == 0) return;
    final next = index.clamp(0, count - 1);
    setState(() => _selected = next);
    _ensureVisible(next, count);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !launcher.visible) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final apps = _apps;
    if (_appById(_menuId) != null) {
      if (key == LogicalKeyboardKey.escape) {
        _closeMenu();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        final count = _menuCanSend ? 2 : 1;
        setState(() => _menuChoice = (_menuChoice + 1) % count);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        final id = _menuId!;
        if (_menuChoice == 0) {
          _launch(id);
        } else if (_menuCanSend) {
          unawaited(_send(id));
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      launcher.onDismiss();
      return KeyEventResult.handled;
    }
    if (apps.isEmpty) return KeyEventResult.ignored;
    final searchFocused = launcher.searchFocusNode.hasFocus;
    if (searchFocused) {
      if (key == LogicalKeyboardKey.tab ||
          key == LogicalKeyboardKey.arrowDown) {
        _gridFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _launch(apps.first.id);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab) {
      launcher.searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed)) {
      final index = _selected.clamp(0, apps.length - 1);
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.destination);
      final list = _listAnchor.currentContext?.findRenderObject() as RenderBox?;
      final panel = context.findRenderObject() as RenderBox?;
      if (list != null && panel != null) {
        final rowTop =
            _applicationIndex.applicationRows[index] * _rowExtent -
            (_scroll.hasClients ? _scroll.offset : 0.0);
        final anchor = list.localToGlobal(Offset(24, rowTop + _rowExtent / 2));
        _openMenuAt(apps[index].id, panel.globalToLocal(anchor));
      }
      return KeyEventResult.handled;
    }
    var delta = 0;
    if (key == LogicalKeyboardKey.arrowDown) delta = 1;
    if (key == LogicalKeyboardKey.arrowUp) delta = -1;
    if (key == LogicalKeyboardKey.pageDown) delta = 8;
    if (key == LogicalKeyboardKey.pageUp) delta = -8;
    if (key == LogicalKeyboardKey.home) delta = -apps.length;
    if (key == LogicalKeyboardKey.end) delta = apps.length;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _launch(apps[_selected.clamp(0, apps.length - 1)].id);
      return KeyEventResult.handled;
    }
    if (delta == 0) return KeyEventResult.ignored;
    _moveTo(moveSelection(_selected, delta, apps.length), apps.length);
    return KeyEventResult.handled;
  }

  /// Host font and CJK fallbacks are taken from the shell text theme so the
  /// launcher never silently falls back to a bundled Material font.
  ShellThemeData? _materialSource;
  ThemeData? _materialCache;
  ThemeData _materialTheme(ShellThemeData shell) {
    if (identical(_materialSource, shell) && _materialCache != null) {
      return _materialCache!;
    }
    _materialSource = shell;
    final base = shell.toMaterialTheme();
    TextStyle style(
      double size,
      FontWeight weight,
      Color color, {
      double height = 1.3,
    }) => shell.text.base.copyWith(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
    final text = TextTheme(
      titleLarge: style(20, FontWeight.w600, shell.colors.textPrimary),
      titleMedium: style(16, FontWeight.w600, shell.colors.textPrimary),
      titleSmall: style(14, FontWeight.w600, shell.colors.textPrimary),
      bodyLarge: style(14, FontWeight.w400, shell.colors.textPrimary),
      bodyMedium: style(13, FontWeight.w400, shell.colors.textPrimary),
      bodySmall: style(12, FontWeight.w400, shell.colors.textSecondary),
      labelLarge: style(14, FontWeight.w500, shell.colors.textPrimary),
      labelMedium: style(12, FontWeight.w500, shell.colors.textSecondary),
      labelSmall: style(11, FontWeight.w400, shell.colors.textTertiary),
    );
    return _materialCache = base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: NoSplash.splashFactory,
      iconTheme: IconThemeData(color: shell.colors.textSecondary, size: 18),
      dividerTheme: DividerThemeData(
        color: shell.colors.hairlineSoft,
        thickness: 1,
        space: 1,
      ),
    );
  }

  Widget _iconButton(
    ShellThemeData shell,
    IconData icon,
    VoidCallback onPressed,
    String tooltip,
  ) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      style: IconButton.styleFrom(
        foregroundColor: shell.colors.textSecondary,
        hoverColor: shell.accentPalette.subtle,
        highlightColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: shell.borderRadius(4)),
      ),
      icon: Icon(icon),
    );
  }

  Widget _searchField(ShellThemeData shell) {
    final radius = shell.borderRadius(4);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: shell.colors.hairline),
    );
    return TextField(
      controller: _search,
      focusNode: launcher.searchFocusNode,
      mouseCursor: launcher.textCursor,
      cursorColor: shell.accentPalette.primary,
      cursorWidth: 1.6,
      style: shell.text.base.copyWith(
        fontSize: 14,
        color: shell.colors.textPrimary,
      ),
      textAlignVertical: TextAlignVertical.center,
      onTap: () => _closeMenu(restoreSearch: false),
      onChanged: (_) {
        setState(() {
          _selected = 0;
          _menuId = null;
        });
        _resetScroll();
      },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: shell.cardColor(shell.colors.surfaceContainerHigh),
        hintText: launcher.strings.searchApplications,
        hintStyle: shell.text.base.copyWith(
          fontSize: 14,
          color: shell.colors.textTertiary,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: shell.colors.textSecondary,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 42,
          minHeight: 36,
        ),
        suffixIcon: _search.text.isEmpty
            ? null
            : _iconButton(shell, Icons.clear, () {
                _search.clear();
                setState(() => _selected = 0);
                _resetScroll();
                launcher.searchFocusNode.requestFocus();
              }, launcher.strings.clearSearch),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 34,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: shell.accentPalette.primary),
        ),
      ),
    );
  }

  Widget _row(
    LauncherApplication app,
    int index,
    int selected,
    ShellThemeData shell,
  ) {
    final isSelected = _gridFocus.hasFocus && index == selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        cursor: launcher.linkCursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _launch(app.id),
          onSecondaryTapDown: (details) =>
              _openMenu(app.id, details.globalPosition),
          child: LauncherHighlight(
            theme: shell,
            selected: isSelected,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: launcher.buildIcon(context, app.id),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shell.text.base.copyWith(
                        fontSize: 13,
                        color: shell.colors.textPrimary,
                        height: 1.2,
                      ),
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

  Widget _emptyState(ShellThemeData shell) {
    final loading = launcher.applications.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              loading ? Icons.hourglass_empty : Icons.search_off,
              size: 28,
              color: shell.colors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              loading
                  ? launcher.strings.loadingApplications
                  : launcher.strings.noApplicationsFound,
              textAlign: TextAlign.center,
              style: shell.text.base.copyWith(
                fontSize: 13,
                color: shell.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    ShellThemeData shell, {
    required int index,
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    final selected = _menuChoice == index;
    final color = enabled
        ? shell.colors.textPrimary
        : shell.colors.textTertiary;
    return MouseRegion(
      cursor: enabled ? launcher.linkCursor : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled && _menuChoice != index) {
          setState(() => _menuChoice = index);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          height: subtitle == null ? _menuRowExtent : _menuSubtitleExtent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected && enabled
                ? shell.accentPalette.subtle
                : Colors.transparent,
            borderRadius: shell.borderRadius(4),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled
                    ? shell.colors.textSecondary
                    : shell.colors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shell.text.base.copyWith(
                        fontSize: 13,
                        color: color,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: shell.text.base.copyWith(
                          fontSize: 11,
                          color: shell.colors.textTertiary,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(
    ShellThemeData shell,
    LauncherApplication app,
    double width,
    double height,
  ) {
    final extent =
        _menuRowExtent +
        8 +
        (_menuCanSend ? _menuRowExtent : _menuSubtitleExtent);
    final left = _menuPosition.dx.clamp(
      8.0,
      math.max(8.0, width - _menuWidth - 8),
    );
    final top = _menuPosition.dy.clamp(8.0, math.max(8.0, height - extent - 8));
    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: math.min(_menuWidth, math.max(0.0, width - 16)),
      child: Focus(
        focusNode: _menuFocus,
        onKeyEvent: _key,
        child: Material(
          elevation: 12,
          shadowColor: shell.colors.shadow,
          color: shell.panelColor(shell.colors.surfaceContainerHigh),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: shell.borderRadius(8),
            side: BorderSide(color: shell.colors.hairlineSoft),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _menuItem(
                  shell,
                  index: 0,
                  icon: Icons.open_in_new,
                  label: tr('打开', 'Open'),
                  enabled: true,
                  onTap: () => _launch(app.id),
                ),
                _menuItem(
                  shell,
                  index: 1,
                  icon: Icons.desktop_windows_outlined,
                  label: tr('发送快捷方式到桌面', 'Send shortcut to desktop'),
                  subtitle: _menuCanSend
                      ? null
                      : tr(
                          '此应用没有可用的 .desktop 入口',
                          'No desktop entry available',
                        ),
                  enabled: !_busy && _menuCanSend,
                  onTap: () => unawaited(_send(app.id)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(ShellThemeData shell, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: shell.text.base.copyWith(
          fontSize: 12,
          height: 1.2,
          color: shell.colors.textSecondary,
        ),
      ),
    ),
  );

  Widget _applicationList(ShellThemeData shell) {
    final index = _applicationIndex;
    final apps = index.applications;
    return KeyedSubtree(
      key: _listAnchor,
      child: apps.isEmpty
          ? _emptyState(shell)
          : Focus(
              focusNode: _gridFocus,
              onFocusChange: (_) => setState(() {}),
              child: Scrollbar(
                controller: _scroll,
                thickness: 4,
                radius: const Radius.circular(2),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: Listener(
                    onPointerSignal: _scroll.observeSignal,
                    child: ListView.builder(
                      key: const PageStorageKey("app-shelf-list"),
                      controller: _scroll,
                      padding: EdgeInsets.zero,
                      itemExtent: _rowExtent,
                      itemCount: index.rows.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<(bool, String)>) return null;
                        final (application, id) = key.value;
                        return application
                            ? index.applicationRowById[id]
                            : index.headingRows[id];
                      },
                      itemBuilder: (context, row) {
                        final entry = index.rows[row];
                        final appIndex = entry.applicationIndex;
                        return appIndex == null
                            ? KeyedSubtree(
                                key: ValueKey((false, entry.heading!)),
                                child: _heading(shell, entry.heading!),
                              )
                            : RetainedLauncherEntry(
                                key: ValueKey((true, apps[appIndex].id)),
                                id: apps[appIndex].id,
                                retention: _rowRetention,
                                child: _row(
                                  apps[appIndex],
                                  appIndex,
                                  _selected.clamp(0, apps.length - 1),
                                  shell,
                                ),
                              );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _tiles(ShellThemeData shell) {
    final recent = _applicationIndex.recent;
    final apps = recent.isEmpty ? _apps.take(9).toList() : recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: _heading(
            shell,
            recent.isEmpty
                ? tr('应用速览', 'Explore apps')
                : tr('最近使用', 'Recently used'),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 330 ? 3 : 2;
              return Listener(
                onPointerSignal: _tileScroll.observeSignal,
                child: GridView.builder(
                  key: const PageStorageKey('app-shelf-tiles'),
                  controller: _tileScroll,
                  padding: const EdgeInsets.fromLTRB(8, 0, 12, 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: apps.length,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final i = apps.indexWhere((app) => app.id == key.value);
                    return i < 0 ? null : i;
                  },
                  itemBuilder: (context, i) {
                    final app = apps[i];
                    return RetainedLauncherEntry(
                      key: ValueKey(app.id),
                      id: app.id,
                      retention: _tileRetention,
                      child: MouseRegion(
                        cursor: launcher.linkCursor,
                        child: GestureDetector(
                          onTap: () => _launch(app.id),
                          onSecondaryTapDown: (d) =>
                              _openMenu(app.id, d.globalPosition),
                          child: LauncherHighlight(
                            theme: shell,
                            idleColor: shell.accentPalette.primary.withValues(
                              alpha: 0.10,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: launcher.buildIcon(
                                          context,
                                          app.id,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      app.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: shell.text.base.copyWith(
                                        fontSize: 12,
                                        color: shell.colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAll() {
    _closeMenu(restoreSearch: false);
    _search.clear();
    setState(() => _selected = 0);
    _resetScroll();
    _gridFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellTheme.of(context);
    final menuApp = _appById(_menuId);
    return IgnorePointer(
      ignoring: !launcher.visible,
      child: ExcludeFocus(
        excluding: !launcher.visible,
        child: MouseRegion(
          onEnter: (_) => launcher.onEnter(),
          onExit: (_) => launcher.onExit(),
          child: Theme(
            data: _materialTheme(shell),
            // The native launcher window owns acrylic composition and placement.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: shell.panelColor(shell.colors.panelBackground),
                borderRadius: BorderRadius.circular(shell.panelRadius),
                border: Border.all(color: shell.colors.hairline),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(shell.panelRadius),
                child: Material(
                  type: MaterialType.transparency,
                  child: Focus(
                    onKeyEvent: _key,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final showTiles =
                            constraints.maxWidth >= 580 &&
                            _search.text.trim().isEmpty;
                        return Stack(
                          children: [
                            if (menuApp != null)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _closeMenu,
                                  onSecondaryTap: _closeMenu,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(1),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: ColoredBox(
                                      color: shell.colors.textPrimary
                                          .withValues(alpha: 0.035),
                                      child: Column(
                                        children: [
                                          const SizedBox(height: 8),
                                          _iconButton(
                                            shell,
                                            Icons.menu,
                                            _showAll,
                                            tr('所有应用', 'All apps'),
                                          ),
                                          const SizedBox(height: 10),
                                          _iconButton(
                                            shell,
                                            Icons.search,
                                            () {
                                              _closeMenu();
                                              launcher.searchFocusNode
                                                  .requestFocus();
                                            },
                                            launcher.strings.searchApplications,
                                          ),
                                          const Spacer(),
                                          _iconButton(
                                            shell,
                                            Icons.close,
                                            launcher.onDismiss,
                                            tr('关闭', 'Close'),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                flex: showTiles ? 4 : 1,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    SizedBox(
                                                      height: 36,
                                                      child: _heading(
                                                        shell,
                                                        _search.text
                                                                .trim()
                                                                .isEmpty
                                                            ? tr(
                                                                '所有应用',
                                                                'All apps',
                                                              )
                                                            : tr(
                                                                '搜索结果 · ${_apps.length}',
                                                                'Results · ${_apps.length}',
                                                              ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: _applicationList(
                                                        shell,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (showTiles)
                                                Expanded(
                                                  flex: 5,
                                                  child: _tiles(shell),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (_notice != null)
                                          SizedBox(
                                            height: 26,
                                            child: Semantics(
                                              liveRegion: true,
                                              child: _heading(shell, _notice!),
                                            ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            6,
                                            10,
                                            8,
                                          ),
                                          child: _searchField(shell),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (menuApp != null)
                              _menu(
                                shell,
                                menuApp,
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                          ],
                        );
                      },
                    ),
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
