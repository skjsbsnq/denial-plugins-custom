/// Keeps SDK initialization defaults from appearing as a real selected mode.
class PowerModePresentation {
  const PowerModePresentation({
    required this.available,
    required this.refreshing,
    required this.changing,
    required this.profile,
  });

  final bool available;
  final bool refreshing;
  final bool changing;
  final String profile;

  bool get canSelect => available && !refreshing && !changing;
  bool isSelected(String value) => available && profile == value;
}

/// UPower exposes watts and volts, so label this derived current as an estimate.
double? estimatedBatteryCurrent(double? watts, double? volts) {
  if (watts == null ||
      volts == null ||
      !watts.isFinite ||
      !volts.isFinite ||
      volts <= 0 ||
      watts < 0) {
    return null;
  }
  final value = watts / volts * 1000;
  return value.isFinite ? value : null;
}
