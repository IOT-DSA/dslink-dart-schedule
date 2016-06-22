import "package:dslink_schedule/ical.dart";

main() async {
  print(serializeCalendarValue({
    "FREQ": "DAILY",
    "UNTIL": "Hello"
  }));
}
