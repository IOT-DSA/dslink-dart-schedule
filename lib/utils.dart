library dslink.schedule.utils;

import "dart:async";
import "package:dslink/responder.dart";

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

  final int realDuration;

  TimeRange(this.start, this.end, {this.realDuration});

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

void addOrUpdateNode(SimpleNodeProvider provider, String path, Map<String, dynamic> map) {
  if (!provider.hasNode(path)) {
    provider.addNode(path, map);
    return;
  }

  SimpleNode node = provider.getNode(path);
  if (node.configs[r"$is"] != null &&
    map[r"$is"] != null &&
    node.configs[r"$is"] != map[r"$is"]) {
    provider.removeNode(path);
    provider.addNode(path, map);
    return;
  }

  for (String key in map.keys) {
    var value = map[key];
    if (key.startsWith(r"$")) {
      if (node.configs[key] != value) {
        node.configs[key] = value;
        node.updateList(key);
      }
    } else if (key.startsWith(r"@")) {
      if (node.attributes[key] != value) {
        node.attributes[key] = value;
        node.updateList(key);
      }
    } else if (key == "?value") {
      node.updateValue(value);
    } else if (value is Map) {
      var p = path;
      if (!p.endsWith("/")) {
        p += "/";
      }
      p += key;
      addOrUpdateNode(provider, p, value);
    }
  }
}

int toInt(input) {
  if (input is num) {
    return input.toInt();
  }

  if (input is String) {
    return num.parse(input, (_) => 0.0).toInt();
  }

  return 0;
}
