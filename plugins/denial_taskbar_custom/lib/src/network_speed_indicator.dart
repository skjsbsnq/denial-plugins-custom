import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_speed.dart';
import 'network_telemetry_state.dart';
import 'neutral_color.dart';

const _networkSpeedPadding = EdgeInsets.symmetric(horizontal: 4);

TextStyle? _networkSpeedStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
      color: taskbarForeground(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Reserve a stable slot for the full rate, including the rounding boundary
/// (999.95 KB/s can display as 1000.0 KB/s). Measure with the actual font and
/// text scaler rather than capping accessibility text at a fixed width.
double networkSpeedIndicatorWidth(BuildContext context) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  );
  final style = DefaultTextStyle.of(context).style
      .merge(_networkSpeedStyle(context));
  var width = 80.0;
  for (final arrow in ['↑', '↓']) {
    for (final unit in ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s']) {
      painter.text = TextSpan(text: '$arrow 1000.0 $unit', style: style);
      painter.layout();
      final required =
          painter.width.ceilToDouble() + _networkSpeedPadding.horizontal;
      if (required > width) width = required;
    }
  }
  painter.dispose();
  return width;
}

/// Two-line readout; the parent popup button supplies its click/focus target.
class NetworkSpeedIndicator extends ConsumerWidget {
  const NetworkSpeedIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(networkTelemetryProvider).value?.speed;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final upload = formatNetworkSpeed(speed?.upload);
    final download = formatNetworkSpeed(speed?.download);
    final style = _networkSpeedStyle(context);
    return IgnorePointer(
      child: Semantics(
        label: zh
            ? '网络速度，上传 $upload，下载 $download'
            : 'Network speed, upload $upload, download $download',
        child: ExcludeSemantics(
          child: Padding(
            padding: _networkSpeedPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('↑ $upload', style: style, maxLines: 1, softWrap: false),
                Text('↓ $download', style: style, maxLines: 1, softWrap: false),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
