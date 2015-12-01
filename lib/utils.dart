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
