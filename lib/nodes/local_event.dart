import 'package:dslink/dslink.dart';

import 'common.dart';
import "../calendar.dart";
import "../ical.dart" as ical;
import '../utils.dart';

class AddLocalEventNode extends SimpleNode {
  static const String isType = 'addLocalEvent';
  static const String pathName = 'addEvent';

  static const String _name = 'name';
  static const String _time = 'time';
  static const String _value = 'value';
  static const String _rule = 'rule';

  static Map<String, dynamic> def() => {
    r"$name": "Add Event",
    r"$is": isType,
    r"$invokable": "write",
    r"$params": [
      {
        "name": _name,
        "type": "string",
        "placeholder": "Turn on Light"
      },
      {
        "name": _time,
        "type": "string",
        "editor": "daterange"
      },
      {
        "name": _value,
        "type": "dynamic",
        "description": "Event Value"
      },
      {
        "name": _rule,
        "type": "string",
        "placeholder": "FREQ=DAILY"
      }
    ]
  };

  AddLocalEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params[_name];
    var timeRangeString = params[_time];
    var value = parseInputValue(params[_value]);
    var ruleString = params[_rule];

    if (name is! String) {
      throw new Exception("Invalid Event Name");
    }

    if (timeRangeString is! String) {
      throw new Exception("Invalid Event Times");
    }

    DateTime start;
    DateTime end;
    Map rule;

    {
      var parts = timeRangeString.split("/");
      start = DateTime.parse(parts[0]);
      end = DateTime.parse(parts[1]);
    }

    TimeRange range = new TimeRange(start, end);

    if (ruleString != null && ruleString.toString().isNotEmpty) {
      rule = ical.tokenizePropertyList(ruleString);
    }

    var event = new ical.StoredEvent(name, value, range);

    if (rule != null && rule.isNotEmpty) {
      event.rule = rule;
    }

    var p = new Path(path);
    ICalendarLocalSchedule schedule = provider.getNode(p.parent.parent.path);
    schedule.addStoredEvent(event);
  }
}

class EditLocalEventNode extends SimpleNode {
  static const String isType = 'editLocalEvent';

  static const String _name = 'name';
  static const String _time = 'time';
  static const String _value = 'value';
  static const String _rule = 'rule';

  static Map<String, dynamic> def(EventDescription event, String rule) => {
    r"$name": "Edit",
    r"$params": [
      {
        "name": _name,
        "type": "string",
        "default": event.name
      },
      {
        "name": _time,
        "type": "string",
        "editor": "daterange",
        "default": "${event.start}/${event.end}"
      },
      {
        "name": _value,
        "type": "dynamic",
        "default": event.value
      },
      {
        "name": _rule,
        "type": "string",
        "placeholder": "FREQ=DAILY",
        "default": rule
      }
    ],
    r"$is": isType,
    r"$invokable": "write"
  };

  EditLocalEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params[_name];
    var timeRangeString = params[_time];
    var ruleString = params[_rule];
    var val = params[_value];

    var p = new Path(path);

    ICalendarLocalSchedule schedule = provider.getNode(p.parent.parent.parent.path);

    String eventId = p.parent.name;
    if (eventId == null) {
      throw new Exception("Failed to resolve event.");
    }

    DateTime start;
    DateTime end;
    Map rule;

    if (timeRangeString is String) {
      var parts = timeRangeString.split("/");
      start = DateTime.parse(parts[0]);
      end = DateTime.parse(parts[1]);
    }

    if (ruleString is String && ruleString.isNotEmpty) {
      rule = ical.tokenizePropertyList(ruleString);
    }

    var m = {
      'name': name,
      'start': start?.toIso8601String(),
      'end': end?.toIso8601String(),
      'rule': rule,
      'value': parseInputValue(val)
    };

    await schedule.updateStoredEvent(eventId, m);

  }
}
