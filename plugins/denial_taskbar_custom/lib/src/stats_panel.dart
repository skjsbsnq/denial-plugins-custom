// Layout inspired by Stats (MIT), Copyright (c) 2019 Serhiy Mytrovtsiy.
// See third_party/stats-LICENSE.
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({
    required this.title,
    required this.icon,
    required this.onClose,
    required this.children,
    this.onRefresh,
    super.key,
  });
  final String title;
  final IconData icon;
  final VoidCallback onClose;
  final VoidCallback? onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final shell = context.shellTheme;
    final radius = BorderRadius.circular(shell.panelRadius);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return ShellBackdropBlur(
      blur: shell.effectivePanelOpacity < 1,
      separateChild: true,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shell.panelColor(context.shellColors.panelBackground),
          borderRadius: radius,
        ),
        // Keep the foreground's display list independent of reveal/translation
        // and backdrop painting, as in the control center.
        child: RepaintBoundary(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 46,
                    child: Row(
                      children: [
                        if (onRefresh != null)
                          IconButton(
                            tooltip: zh ? '刷新' : 'Refresh',
                            onPressed: onRefresh,
                            icon: Icon(icon, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                          )
                        else
                          SizedBox(
                            width: 32,
                            child: Icon(
                              icon,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: zh ? '关闭' : 'Close',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatsSection extends StatelessWidget {
  const StatsSection(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const Expanded(child: Divider(height: 1)),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const Expanded(child: Divider(height: 1)),
      ],
    ),
  );
}

class StatsRow extends StatelessWidget {
  const StatsRow(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}
