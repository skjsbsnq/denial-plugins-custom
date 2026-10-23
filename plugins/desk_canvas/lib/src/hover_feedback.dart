// SPDX-License-Identifier: GPL-3.0-or-later
/// Pointer feedback is temporary and independent of the selection set. After
/// a popup/launch/focus change, synthetic re-entry must not relight an icon.
class DesktopHoverFeedback {
  bool hovered = false;
  bool _requiresMotion = false;
  void reset() {
    hovered = false;
    _requiresMotion = true;
  }

  bool update({required bool inside, bool moved = false}) {
    final before = hovered;
    if (!inside) {
      hovered = false;
    } else if (moved || !_requiresMotion) {
      hovered = true;
      _requiresMotion = false;
    }
    return hovered != before;
  }
}
