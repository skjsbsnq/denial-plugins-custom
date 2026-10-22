import 'package:flutter/material.dart';

import 'network_detail_layout.dart';

/// Preserve names and addresses as single strings, without scaling or truncation.
class NetworkDetailRow extends StatelessWidget {
  const NetworkDetailRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .merge(Theme.of(context).textTheme.bodyMedium);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final placement = networkDetailLayout(
            availableWidth: constraints.maxWidth,
            labelWidth: measure(label),
            valueWidth: measure(value),
          );
          final text = Tooltip(
            message: value,
            child: SelectionArea(
              child: Text(value, style: style, softWrap: false, maxLines: 1),
            ),
          );
          final contents = placement.scrollValue
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: text,
                )
              : text;
          if (placement.stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: style),
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: contents,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: style),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: contents,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
