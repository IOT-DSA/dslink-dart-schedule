library dslink.schedule.utils;

import "dart:async";

dynamic parseInputValue(input) {
  if (input == null) return null;

  if (input is! String) {
    return input;
  }

  var lowerTrimmed = input.trim().toLowerCase();

  if (lowerTrimmed == "true" || lowerTrimmed == "false") {
    return lowerTrimmed == "true";
  }

  var number = num.parse(input, (source) => null);

  if (number != null) {
    return number;
  }

  return input;
}

class TimeRange {
  final DateTime start;
  final DateTime end;

  TimeRange(this.start, this.end);

  @override
  String toString() {
    return "TimeRange(${start} to ${end})";
  }
}

class TimeUtils {
  static DateTime get now {
    var mocked = Zone.current["mock.time"];
    if (mocked == null) {
      return new DateTime.now();
    }

    if (mocked is DateTime) {
      return mocked;
    }

    if (mocked is Function) {
      return mocked();
    }

    return new DateTime.now();
  }
}

String formatICalendarTime(DateTime time) {
  var out = "";
  out += time.year.toString().padLeft(4, "0");
  out += time.month.toString().padLeft(2, "0");
  out += time.day.toString().padLeft(2, "0");
  out += "T";
  out += time.hour.toString().padLeft(2, "0");
  out += time.minute.toString().padLeft(2, "0");
  out += time.second.toString().padLeft(2, "0");
  return out;
}
