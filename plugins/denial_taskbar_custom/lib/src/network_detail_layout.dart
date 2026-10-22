/// Use actual text widths instead of reserving half of every row for labels.
/// Long values get a full-width line and scroll only if that is still too narrow.
({bool stacked, bool scrollValue}) networkDetailLayout({
  required double availableWidth,
  required double labelWidth,
  required double valueWidth,
  double gap = 12,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : 0.0;
  return (
    stacked: labelWidth + gap + valueWidth > width,
    scrollValue: valueWidth > width,
  );
}
