import 'dart:async';

import 'package:dslink/dslink.dart';

import 'package:dslink_schedule/calendar.dart';

import 'local_schedules.dart' show ICalendarLocalSchedule;

class EventNode extends SimpleNode {
  EventDescription description;
  bool flagged = false;

  EventNode(String path) : super(path);

  @override
  onRemoving() {
    var p = new Path(path);
    var node = provider.getNode(p.parent.parent.path);
    if (node is ICalendarLocalSchedule && !flagged) {
      node.storedEvents.removeWhere((x) => x["name"] == description.name);
      node.loadSchedule();
    }
  }

  @override
  void load(Map input) {
    if (input["?description"] is EventDescription) {
      description = input["?description"];
    }
    super.load(input);
  }
}

class FetchEventsNode extends SimpleNode {
  static const String pathName = 'fetchEvents';
  static const String isType = 'fetchEvents';

  // Params
  static const String _timeRange = 'TimeRange';

  // Columns (return values)
  static const String _start = 'start';
  static const String _end = 'end';
  static const String _dur = 'duration';
  static const String _evt = 'event';
  static const String _val = 'value';

  static Map<String, dynamic> def() => {
    r"$name": "Fetch Events",
    r"$invokable": "read",
    r"$is": isType,
    r"$params": [
      {
        "name": "TimeRange",
        "type": "string",
        "editor": "daterange"
      }
    ],
    r"$columns": [
      {
        "name": _start,
        "type": "string"
      },
      {
        "name": _end,
        "type": "string"
      },
      {
        "name": _dur,
        "type": "number"
      },
      {
        "name": _evt,
        "type": "string"
      },
      {
        "name": _val,
        "type": "dynamic"
      }
    ],
    r"$result": "table"
  };

  FetchEventsNode(String path) : super(path);

  @override
  Future onInvoke(Map<String, dynamic> params) async {
    String timeRangeString = params[_timeRange];
    DateTime start;
    DateTime end;

    if (timeRangeString is! String || timeRangeString.isEmpty) {
      var err = new ArgumentError.value(timeRangeString, _timeRange,
          'should be a date range string.');
      return new Future.error(err);
    }

    var parts = timeRangeString.split("/");
    try {
      start = DateTime.parse(parts[0]);
      end = DateTime.parse(parts[1]);
    } catch (e) {
      var err = new ArgumentError.value(timeRangeString, _timeRange,
          'failed to parse date: ${e.toString()}');
      return new Future.error(err);
    }

    var schedule = (parent as ICalendarLocalSchedule);

    return schedule.state.getBetween(start, end).map((v) {
      return [
        v.time.toIso8601String(),
        v.endsAt.toIso8601String(),
        v.duration.inMilliseconds,
        v.eventId.toString(),
        v.value
      ];
    }).toList();
  }
}