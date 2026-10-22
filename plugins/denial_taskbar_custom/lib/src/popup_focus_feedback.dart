import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Share one keyboard observer across the taskbar popup toggles. Logical focus
/// still returns after dismissal; only pointer-origin focus paint is hidden.
final popupFocusFeedbackProvider =
    NotifierProvider.autoDispose<PopupFocusFeedback, bool>(
      PopupFocusFeedback.new,
    );

class PopupFocusFeedback extends Notifier<bool> {
  @override
  bool build() {
    bool observeKey(KeyEvent event) {
      if (ref.mounted &&
          !event.synthesized &&
          (event is KeyDownEvent || event is KeyRepeatEvent)) {
        state = true;
      }
      // Observe even keys handled by shortcuts, without consuming them.
      return false;
    }

    HardwareKeyboard.instance.addHandler(observeKey);
    ref.onDispose(() => HardwareKeyboard.instance.removeHandler(observeKey));
    return false;
  }

  void pointerInteraction() => state = false;
}

ButtonStyle popupButtonFocusStyle(ButtonStyle base, {required bool keyboard}) =>
    base.copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (!keyboard &&
            states.contains(WidgetState.focused) &&
            !states.contains(WidgetState.hovered) &&
            !states.contains(WidgetState.pressed)) {
          return Colors.transparent;
        }
        // Preserve each button's own hover/press colors and theme defaults.
        return base.overlayColor?.resolve(states);
      }),
    );
