import 'dart:async';

import 'package:dslink/dslink.dart';
import "package:timezone/src/env.dart" as TimezoneEnv;

import 'common.dart';

class TimezoneNode extends SimpleNode {
  static const String isType = "timezone";
  static const String pathName = "timezone";

  static Map<String, dynamic> def(String tz) => {
    r"$name": "Timezone",
    r"$type": "string",
    r"$is": isType,
    "?value": tz,
    r"$writable": "write"
  };

  ICalendarLocalSchedule schedule;

  final LinkProvider link;
  TimezoneNode(String path, this.link) : super(path);

  @override
  onSetValue(value) {
    if (value is String) {
      var loc = const [
        "UTC",
        "Etc/GMT"
      ].contains(value) ? TimezoneEnv.UTC : TimezoneEnv.getLocation(value);
      if (loc != null) {
        schedule.timezone = loc;
        schedule.loadSchedule(true);

        link.save();
        return false;
      }
    }
    return true;
  }
}
