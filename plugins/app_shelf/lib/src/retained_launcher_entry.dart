// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/widgets.dart';

import 'entry_retention.dart';

/// Keeps recently visited SDK icon loaders alive within a bounded row budget.
class RetainedLauncherEntry extends StatefulWidget {
  const RetainedLauncherEntry({
    super.key,
    required this.id,
    required this.retention,
    required this.child,
  });
  final String id;
  final EntryRetention retention;
  final Widget child;
  @override
  State<RetainedLauncherEntry> createState() => _RetainedLauncherEntryState();
}

class _RetainedLauncherEntryState extends State<RetainedLauncherEntry>
    with AutomaticKeepAliveClientMixin {
  EntryLease? _lease;
  @override
  void initState() {
    super.initState();
    _acquire();
  }

  void _acquire() {
    _lease = widget.retention.acquire(widget.id, () {
      // Slivers may acquire a new row during layout. Release a cached row only
      // after that frame so keep-alive parent data never changes during layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) updateKeepAlive();
      });
    });
  }

  @override
  void didUpdateWidget(covariant RetainedLauncherEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.retention != widget.retention) {
      oldWidget.retention.release(_lease!);
      _acquire();
      updateKeepAlive();
    }
  }

  @override
  // The mixin consults this from super.initState, before a lease is acquired.
  bool get wantKeepAlive => _lease?.retained ?? false;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  void dispose() {
    widget.retention.release(_lease!);
    super.dispose();
  }
}
