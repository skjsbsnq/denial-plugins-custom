import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'control_center_layout.dart';

/// Bottom-anchored, content-sized panels otherwise inherit a fractional top
/// edge from their measured height, even if their bottom edge was snapped.
class PixelAlignedPanel extends SingleChildRenderObjectWidget {
  const PixelAlignedPanel({
    required this.devicePixelRatio,
    required super.child,
    super.key,
  });
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPixelAlignedPanel(devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderPixelAlignedPanel).devicePixelRatio =
        devicePixelRatio;
  }
}

class _RenderPixelAlignedPanel extends RenderProxyBox {
  _RenderPixelAlignedPanel(this._devicePixelRatio);
  double _devicePixelRatio;

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final content = child;
    if (content == null) {
      size = constraints.smallest;
      return;
    }
    content.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        content.size.width,
        ceilToPhysicalPixel(content.size.height, _devicePixelRatio),
      ),
    );
    // Only the subpixel remainder is added. Keep both edges and the foreground
    // on the same grid without scaling text or forcing a full-height panel.
    if (size != content.size) {
      content.layout(BoxConstraints.tight(size), parentUsesSize: true);
    }
  }
}
