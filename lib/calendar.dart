library dslink.schedule.calendar;

import "dart:async";

import "package:dslink/utils.dart";

import "utils.dart";

abstract class CalendarProvider {
  ValueAtTime next(ValueCalendarState state);
  ValueAtTime current(ValueCalendarState state);
  List<EventDescription> listEvents();
  List<ValueAtTime> between(
    ValueCalendarState state,
    DateTime start,
    DateTime end);
}

class ValueCalendarState {
  final CalendarProvider provider;

  ValueCalendarState(this.provider);

  ValueAtTime defaultValue;

  ValueAtTime getNext() {
    return provider.next(this);
  }

  List<ValueAtTime> getBetween(DateTime start, DateTime end) {
    return Zone.current.fork(zoneValues: {
      "mock.time": start
    }).run(() {
      return provider.between(this, start, end);
    });
  }

  ValueAtTime getCurrent() {
    return provider.current(this);
  }

  List<FunctionDisposable> _listeners = [];

  int lid = 0;

  FunctionDisposable listen(onValueUpdate(ValueAtTime v)) {
    Timer timer;
    Timer timer2;

    var id = lid++;

    check() {
      var current = getCurrent();
      if (current == null) {
        onValueUpdate(defaultValue);
        return;
      }

      Duration nextCheck;

      if (current.isHappeningNow) {
        if (!current.deliveredTo.contains(id)) {
          if (timer2 != null) {
            timer2.cancel();
          }
          current.deliveredTo.add(id);
          onValueUpdate(current);
          timer2 = new Timer(current.duration, () {
            onValueUpdate(defaultValue);
          });
        }
        nextCheck = current.endsIn;
      } else {
        onValueUpdate(defaultValue);
        nextCheck = current.time.difference(TimeUtils.now).abs();
      }

      if (const bool.fromEnvironment("debug.next.check", defaultValue: false)) {
        print(
          "[${current.description.name}] Next check "
          " in ${nextCheck.inSeconds} seconds"
        );
      }

      timer = new Timer(nextCheck, () {
        if (!current.deliveredTo.contains(id)) {
          if (timer2 != null) {
            timer2.cancel();
          }
          current.deliveredTo.add(id);
          onValueUpdate(current);
          timer2 = new Timer(current.duration, () {
            onValueUpdate(defaultValue);
          });
        }
        check();
      });
    }

    check();

    var disposable = new FunctionDisposable(() {
      if (timer != null) {
        timer.cancel();
      }

      if (timer2 != null) {
        timer2.cancel();
      }
    });

    _listeners.add(disposable);

    return disposable;
  }

  void dispose() {
    _listeners.forEach((x) => x.dispose());
    _listeners.clear();
  }
}

class ValueAtTime {
  final DateTime time;
  final dynamic value;
  final Duration duration;
  final EventDescription description;
  final bool isDefault;
  final String eventId;

  ValueAtTime(
    this.time,
    this.value,
    this.duration,
    this.description,
    this.eventId, [
      this.isDefault = false
    ]);

  factory ValueAtTime.forDefault(val) {
    return new ValueAtTime(
      new DateTime.fromMillisecondsSinceEpoch(0),
      val,
      const Duration(days: 36500000),
      new EventDescription("Default", val),
      null,
      true
    );
  }

  DateTime _ended;

  Set<int> deliveredTo = new Set<int>();

  DateTime get endsAt {
    if (_ended == null) {
      _ended = time.add(duration);
    }
    return _ended;
  }

  Duration get until => time.difference(TimeUtils.now);

  Duration get endsIn {
    return endsAt.difference(TimeUtils.now);
  }

  bool get hasAlreadyHappened {
    var now = TimeUtils.now;
    return endsAt.isBefore(now) ||
      endsAt.isAtSameMomentAs(now) ||
      endsAt.difference(now).inSeconds == 0;
  }

  bool get isHappeningNow {
    var now = TimeUtils.now;
    return time.isBefore(now) &&
      endsAt.isAfter(now);
  }

  @override
  String toString() => "ValueAtTime(${time}, ${value})";
}

class EventDescription {
  final String name;

  dynamic value;
  Duration duration;
  DateTime start;
  DateTime end;
  bool isRecurring = false;
  Map rule;

  String uuid;

  EventDescription(this.name, this.value);

  Map asNode(int i) {
    var map = {
      r"$is": "event",
      "?description": this,
      r"$name": name,
      "id": {
        r"$name": "ID",
        r"$type": "string",
        "?value": uuid == null ? i.toString() : uuid
      },
      "value": {
        r"$name": "Value",
        r"$type": "dynamic",
        "?value": value
      }
    };

    if (duration != null) {
      map["duration"] = {
        r"$name": "Duration",
        r"$type": "number",
        "?value": duration.inSeconds,
        "@unit": "seconds"
      };
    }

    map["fetchEvents"] = {
      r"$name": "Fetch Events",
      r"$invokable": "read",
      r"$is": "fetchEventsForEvent",
      r"$params": [
        {
          "name": "TimeRange",
          "type": "string",
          "editor": "daterange"
        }
      ],
      r"$columns": [
        {
          "name": "start",
          "type": "string"
        },
        {
          "name": "end",
          "type": "string"
        },
        {
          "name": "duration",
          "type": "number"
        },
        {
          "name": "event",
          "type": "string"
        },
        {
          "name": "value",
          "type": "dynamic"
        }
      ],
      r"$result": "table"
    };

    String ruleString = "";

    {
      for (var key in rule.keys) {
        var val = rule[key];

        ruleString += "${key}=${val};";
      }

      if (ruleString.endsWith(";")) {
        ruleString = ruleString.substring(0, ruleString.length - 1);
      }
    }

    map["rule"] = {
      r"$name": "Rule",
      r"$type": "string",
      "?value": ruleString
    };

    map["remove"] = {
      r"$name": "Remove",
      r"$invokable": "write",
      r"$is": "remove"
    };

    if (!isRecurring) {
      map["start"] = {
        r"$name": "Start",
        r"$type": "string",
        "?value": start.toIso8601String()
      };

      map["end"] = {
        r"$name": "End",
        r"$type": "string",
        "?value": end.toIso8601String()
      };
    }

    return map;
  }
}
