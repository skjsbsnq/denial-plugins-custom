/// A repeatable hop with zero velocity and acceleration at each landing.
/// The exact zero endpoints keep the resting icon on its original pixels.
double launchBounceHeight(double progress) {
  if (!progress.isFinite || progress <= 0 || progress >= 1) return 0;
  final arch = progress * (1 - progress);
  return 64 * arch * arch * arch;
}

Duration launchBounceDuration(double scale) => !scale.isFinite || scale <= 0
    ? Duration.zero
    : Duration(microseconds: (600000 * scale).round());

// Foreground scroll viewports allow this much upward paint overflow while
// retaining their horizontal clips and original input/layout bounds.
const launchBounceMaxTravel = 18.0;

double launchBounceTravel(double panelTravel) => panelTravel.isFinite
    ? (panelTravel / 32 * launchBounceMaxTravel).clamp(
        0.0,
        launchBounceMaxTravel,
      )
    : 0;
