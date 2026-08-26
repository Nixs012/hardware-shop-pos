class DateRangeHelper {
  // "Daily" = calendar day in shop's local timezone (not UTC)
  // "Weekly" = Monday-Sunday
  // "Monthly" = calendar month

  static DateTime getStartOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime getEndOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  static DateTime getStartOfWeek(DateTime date) {
    int daysToSubtract = date.weekday - DateTime.monday;
    DateTime startOfWeek = date.subtract(Duration(days: daysToSubtract));
    return getStartOfDay(startOfWeek);
  }

  static DateTime getStartOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }
}
