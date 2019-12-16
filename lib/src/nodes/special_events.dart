import 'dart:async';
import 'dart:convert';

import 'package:dslink/dslink.dart';
import 'package:dslink/utils.dart';

import 'local_schedules.dart';

class AddSpecialEventNode extends SimpleNode {
  static const String isType = 'addLocalSpecialEvent';
  static const String pathName = 'addSpecialEvent';

  // Params
  static const String _name = 'Name';
  static const String _type = 'Type';
  static const String _date = 'Date';
  static const String _times = 'Times';
  static const String _replaceId = 'ReplacementId';

  // Columns (return values)
  static const String _createdId = 'CreatedId';


  static Map<String, dynamic> def() => {
    r"$name": "Add Special Event",
    r"$is": isType,
    r"$params": [
      {
        "name": _name,
        "type": "string"
      },
      {
        "name": _type,
        "type": "enum[Date,DateRange]"
      },
      {
        "name": _date,
        "type": "string",
        "editor": "textarea"
      },
      {
        "name": _times,
        "type": "string",
        "editor": "textarea"
      },
      {
        "name": _replaceId,
        "type": "string"
      }
    ],
    r"$columns": [
      {
        "name": _createdId,
        "type": "string"
      }
    ],
    r"$invokable": "write",
    r"$actionGroup": "Advanced"
  };

  @override
  AddSpecialEventNode(String path) : super(path);

  @override
  Future onInvoke(Map<String, dynamic> params) async {
    // Example date: {"year": 2019, "month": 9, "day": 18, "weekday": "WEDNESDAY"}
    // Example times [{"start": 46800000, "duration": 360000, "value": 42}]

    String name = params[_name];
    String type = params[_type];
    String dateString = params[_date];
    String timesString = params[_times];

    ArgumentError err;
    if (dateString == null || dateString.isEmpty) {
      err = new ArgumentError.value(dateString, _date, 'Expected format: ' +
          '{"year": 2019, "month": 1, "day": 27, "weekday": "MONDAY"}');
      return new Future.error(err);
    }
    var date = JSON.decode(dateString);
    if (date is! Map) {
      // mbutler: Need to use Future.error because otherwise it throws before
      // entering new event loop resulting in DSLink Crash at Invoke rather
      // than caught by the Future
      err = new ArgumentError.value(dateString, _date, 'Expected format: ' +
          '{"year": 2019, "month": 1, "day": 27, "weekday": "MONDAY"}');
      return new Future.error(err);
    }

    if (timesString == null || timesString.isEmpty) {
      err = new ArgumentError.value(timesString, _times, 'Expected format: ' +
          '[{"start": 28800000, "finish" : 32400000, "duration": 3600000, "value": 42}]');
    }
    var times = JSON.decode(timesString);
    if (times is Map) {
      times = [times];
    } else if (times is! List) {
      // mbutler: Need to use Future.error because otherwise it throws before
      // entering new event loop resulting in DSLink Crash at Invoke rather
      // than caught by the Future
      err = new ArgumentError.value(timesString, _times, 'Expected format: ' +
          '[{"start": 28800000, "finish" : 32400000, "duration": 3600000, "value": 42}]');
    } else if (times is List) {
      if (times.isEmpty) {
        err = new ArgumentError.value(timesString, _times, ' Expected format: ' +
            '[{"start": 28800000, "finish" : 32400000, "duration": 3600000, "value": 42}]');
      }

      for (var el in times) {
        if (el is! Map || !(el.containsKey('start') &&
            (el.containsKey('finish') || el.containsKey('duration')))) {
          err = new ArgumentError.value(JSON.encode(el), _times, ' Expected format: ' +
              '[{"start": 28800000, "finish" : 32400000, "duration": 3600000, "value": 42}]');
          break;
        }
      }
    }

    if (err != null) {
      return new Future.error(err);
    }

    var schedule = parent.parent as ICalendarLocalSchedule;

    int ind = -1;
    String id = params[_replaceId];

    if (id == null || id.trim().isEmpty) {
      id = generateToken();
    } else {
      for (var i = 0; i < schedule.specialEvents.length; i++) {
        if (schedule.specialEvents[i]['id'] == id) {
          ind = i;
          break;
        }
      }
    }

    //var fe = schedule.specialEvents.firstWhere((e) => e["id"] == id, orElse: () => null);
    var m = {
      "type": type == null ? "Date" : type,
      "date": date,
      "times": times,
      "name": name,
      "id":  id
    };

    if (ind != -1) {
      schedule.specialEvents[ind] = m;
    } else {
      schedule.specialEvents.add(m);
    }

    await schedule.loadSchedule(true);

    return [[
      id
    ]];
  }
}

class FetchSpecialEventsNode extends SimpleNode {
  static const String isType = 'fetchSpecialEvents';
  static const String pathName = 'fetchSpecialEvents';

  // Columns (return values)
  static const String _id = 'Id';
  static const String _name = 'Name';
  static const String _type = 'Type';
  static const String _date = 'Date';
  static const String _time = 'Times';

  static Map<String, dynamic> def() => {
    r"$name": "Fetch Special Events",
    r"$is": isType,
    r"$columns": [
      {
        "name": _id,
        "type": "string"
      },
      {
        "name": _name,
        "type": "string"
      },
      {
        "name": _type,
        "type": "string"
      },
      {
        "name": _date,
        "type": "string"
      },
      {
        "name": _time,
        "type": "string"
      }
    ],
    r"$result": "table",
    r"$invokable": "read",
    r"$actionGroup": "Advanced"
  };

  FetchSpecialEventsNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async* {
    var schedule = parent.parent as ICalendarLocalSchedule;
    for (Map e in schedule.specialEvents) {
      yield [[
        e["id"],
        e["name"],
        e["type"],
        e["date"],
        e["times"]
      ]];
    }
  }
}

class RemoveSpecialEventNode extends SimpleNode {
  static const String isType = 'removeSpecialEvent';
  static const String pathName = 'removeSpecialEvent';

  // Params
  static const String _id = 'Id';

  static Map<String, dynamic> def() => {
    r"$name": "Remove Special Event",
    r"$invokable": "write",
    r"$params": [
      {
        "name": _id,
        "type": "string"
      }
    ],
    r"$actionGroup": "Advanced",
    r"$is": isType
  };

  final LinkProvider _link;

  RemoveSpecialEventNode(String path, this._link) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var schedule = parent.parent as ICalendarLocalSchedule;
    schedule.specialEvents.removeWhere((e) => e["id"] == params[_id]);
    await schedule.loadSchedule(false);
    _link.save();
  }
}
