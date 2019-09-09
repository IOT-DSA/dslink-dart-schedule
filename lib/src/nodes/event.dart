import 'dart:async';

import 'package:dslink/dslink.dart';

import 'package:dslink_schedule/calendar.dart';

import 'local_schedules.dart' show ICalendarLocalSchedule, EditLocalEventNode;

class EventNode extends SimpleNode {
  static const String isType = 'event';

  static const String _id = 'id';
  static const String _value = 'value';
  static const String _duration = 'duration';
  static const String _rule = 'rule';
  static const String _start = 'start';
  static const String _end = 'end';

  static Map<String, dynamic> def(EventDescription e, int i) {
    String ruleString = '';

    if (e.rule != null) {
      e.rule.forEach((key, val) { ruleString += '$key=$val;'; });
    }

    if (ruleString.endsWith(';')) {
      ruleString = ruleString.substring(0, ruleString.length - 1);
    }

    var map = <String, dynamic> {
      r'$is': isType,
      r'$name': e.name,
      r'?description': e,
      _id: {
        r'$name': 'ID',
        r'$type': 'string',
        r'?value': e.uuid ?? i.toString()
      },
      _value: {
        r'$name': 'Value',
        r'$type': 'dynamic',
        r'?value': e.value
      },
      FetchEventsForEventNode.pathName: FetchEventsForEventNode.def(),
      _rule: {
        r'$name': 'Rule',
        r'$type': 'string',
        r'?value': ruleString
      },
      'remove': {
        r'$is': 'remove',
        r'$name': 'Remove',
        r'$invokable': 'write'
      },
      EditLocalEventNode.pathName: EditLocalEventNode.def(e, ruleString)
    };

    if (e.duration != null) {
      map[_duration] = {
        r'$name': 'Duration',
        r'$type': 'number',
        r'?value': e.duration.inSeconds,
        r'@unit': 'seconds'
      };
    }

    if (e.isRecurring) {
      map[_start] = {
        r'$name': 'Start',
        r'$type': 'string',
        r'?value': e.rawStart.toIso8601String()
      };

      map[_end] = {
        r'$name': 'End',
        r'$type': 'string',
        r'?value': e.rawEnd.toIso8601String()
      };
    }

    return map;
  }

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
          {"name": "TimeRange", "type": "string", "editor": "daterange"}
        ],
        r"$columns": [
          {"name": _start, "type": "string"},
          {"name": _end, "type": "string"},
          {"name": _dur, "type": "number"},
          {"name": _evt, "type": "string"},
          {"name": _val, "type": "dynamic"}
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
      var err = new ArgumentError.value(
          timeRangeString, _timeRange, 'should be a date range string.');
      return new Future.error(err);
    }

    var parts = timeRangeString.split("/");
    try {
      start = DateTime.parse(parts[0]);
      end = DateTime.parse(parts[1]);
    } catch (e) {
      var err = new ArgumentError.value(
          timeRangeString, _timeRange, 'failed to parse date: ${e.toString()}');
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

class FetchEventsForEventNode extends SimpleNode {
  static const String pathName = 'fetchEvents';
  static const String isType = 'fetchEventsForEvent';


  static const String _timeRange = 'TimeRange';

  static Map<String, dynamic> def() => {
    r"$is": isType,
    r"$name": "Fetch Events",
    r"$invokable": "read",
    r"$params": [
      {"name": _timeRange, "type": "string", "editor": "daterange"}
    ],
    r"$columns": [
      {"name": "start", "type": "string"},
      {"name": "end", "type": "string"},
      {"name": "duration", "type": "number"},
      {"name": "event", "type": "string"},
      {"name": "value", "type": "dynamic"}
    ],
    r"$result": "table"
  };

  FetchEventsForEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    String timeRangeString = params["TimeRange"];
    DateTime start;
    DateTime end;

    if (timeRangeString is String) {
      var parts = timeRangeString.split("/");
      start = DateTime.parse(parts[0]);
      end = DateTime.parse(parts[1]);
    }

    var p = new Path(path);
    ICalendarLocalSchedule schedule = provider.getNode(p.parent.parent.parent.path);
    String thatUuid = p.parent.name;

    var results = schedule.state
        .getBetween(start, end)
        .where((v) => v.eventId == thatUuid)
        .where((x) => x.time.isAfter(start) && x.time.isBefore(end))
        .toList();

    results.sort((a, b) => a.time.compareTo(b.time));

    results = results.map((v) {
      return [
        v.time.toIso8601String(),
        v.endsAt.toIso8601String(),
        v.duration.inMilliseconds,
        v.eventId,
        v.value
      ];
    }).toList();

    var list = [];
    var set = new Set();

    for (var x in results) {
      if (set.contains(x[0])) {
        continue;
      }
      set.add(x[0]);
      list.add(x);
    }

    return list;
  }
}
