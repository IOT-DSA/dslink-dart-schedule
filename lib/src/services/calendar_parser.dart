import '../ical.dart';

class CalendarParser {
  CalendarObject parse(String input) {
    final tokens = tokenizeCalendar(input);
    final calendar = parseCalendarObjects(tokens);
    var bob = 1;
    return calendar;
  }
}
