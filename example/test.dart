import "dart:io";

import "package:dslink_schedule/calendar.dart";
import "package:dslink_schedule/ical.dart";

main() async {
  var file = new File.fromUri(Platform.script.resolve("lights.ics"));
  var content = await file.readAsString();
  var events = loadEvents(content).map((x) => new EventInstance(x)).toList();
  var provider = new ICalendarProvider(events);
  var vals = new ValueCalendarState(provider);

  vals.defaultValue = new ValueAtTime.forDefault(0);

  ValueAtTime next;

  vals.listen((ValueAtTime v) {
    print("[At ${new DateTime.now()}] Switch to value of ${v.value} (by ${v.description.name})");
    next = vals.getNext();
    if (next != null) {
      print("[At ${new DateTime.now()}] Next Event is '${next.description.name}' in ${next.until.inSeconds} seconds at ${next.time} (sets to ${next.value})");
    }
  });
}
