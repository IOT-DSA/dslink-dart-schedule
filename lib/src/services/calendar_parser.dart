import '../ical.dart';

class CalendarParser {
  void parse(String input) {
    final tokens = tokenizeCalendar(input);
    final calendar = parseCalendarObjects(tokens);
    var bob = 1;
  }
}
