import 'dart:async' show Future;

import 'package:dslink/dslink.dart';
import "package:timezone/src/env.dart" as TimezoneEnv;

import 'local_schedules.dart' show ICalendarLocalSchedule;

class TimezoneNode extends SimpleNode {
  static const String isType = "timezone";
  static const String pathName = "timezone";

  static Map<String, dynamic> def(String tzName) => {
    r'$is': isType,
    r'$name': 'Timezone',
    r'$type': 'string',
    r'?value': tzName,
    r'$writable': 'write'
  };

  ICalendarLocalSchedule schedule;

  LinkProvider _link;
  TimezoneNode(String path, this._link) : super(path);

  @override
  onSetValue(value) {
    if (value is String) {
      var loc = const [
        "UTC",
        "Etc/GMT"
      ].contains(value) ? TimezoneEnv.UTC : TimezoneEnv.getLocation(value);
      if (loc != null) {
        schedule.timezone = loc;
        new Future(() {
          _link.save();
        });
        schedule.loadSchedule(true);
        return false;
      }
    }
    return true;
  }
}