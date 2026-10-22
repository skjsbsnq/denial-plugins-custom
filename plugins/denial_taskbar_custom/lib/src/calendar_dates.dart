/// Calendar components avoid daylight-saving transitions in 24-hour additions.
List<DateTime> calendarDates(DateTime month, {required int firstWeekday}) {
  final first = DateTime(month.year, month.month);
  final offset = (first.weekday % 7 - firstWeekday) % 7;
  return List.generate(
    42,
    (i) => DateTime(month.year, month.month, 1 - offset + i),
  );
}

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String utcOffsetLabel(Duration offset) {
  final minutes = offset.inMinutes.abs();
  return 'GMT${offset.isNegative ? '-' : '+'}${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}
