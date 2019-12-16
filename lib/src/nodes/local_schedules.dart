import 'dart:async';
import 'dart:convert';

import "package:crypto/crypto.dart";
import 'package:timezone/timezone.dart' as TimezoneEnv;

import 'package:dslink/dslink.dart';
import 'package:dslink/nodes.dart' show NodeNamer;
import 'package:dslink/utils.dart';

import 'package:dslink_schedule/utils.dart';
import 'package:dslink_schedule/calendar.dart';
import "package:dslink_schedule/ical.dart" as ical;

import 'timezone.dart';
import 'event.dart';
import 'special_events.dart';

class AddICalLocalScheduleNode extends SimpleNode {
  static const String pathName = "addiCalLocalSchedule";
  static const String isType = "addiCalLocalSchedule";

  // Params
  static const String _name = "name";
  static const String _defaultValue = "defaultValue";

  static Map<String, dynamic> def() => {
        r"$is": isType,
        r"$name": "Add Local Schedule",
        r"$params": [
          {
            "name": _name,
            "type": "string",
            "placeholder": "Light Schedule",
            "description": "Name of the Schedule"
          },
          {
            "name": _defaultValue,
            "type": "dynamic",
            "description": "Default Value for Schedule",
            "default": 0
          }
        ],
        r"$invokable": "write"
      };

  final LinkProvider _link;
  AddICalLocalScheduleNode(String path, this._link) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    String name = params[_name];
    dynamic def = params[_defaultValue];

    def = parseInputValue(def);

    var rawName = NodeNamer.createName(name);
    provider.addNode("/$rawName", ICalendarLocalSchedule.def(name, def));

    _link.save();
  }
}

class ICalendarLocalSchedule extends SimpleNode {
  static const String isType = 'iCalLocalSchedule';

  // Values
  static const String _current = 'current';
  static const String _next = 'next';
  static const String _next_ts = 'next_ts';
  static const String _stc = 'stc';
  static const String _remove = 'remove';
  static const String _events = 'events';

  static Map<String, dynamic> def(String name, dynamic defaultValue) => {
        r'$name': name,
        r"$is": isType,
        "@defaultValue": defaultValue,
        _current: {r'$name': 'Current Value', r'$type': 'dynamic'},
        _next: {r'$name': 'Next Value', r'$type': 'dynamic'},
        _next_ts: {r"$name": "Next Value Timestamp", r"$type": "dynamic"},
        _stc: {
          r"$name": "Next Value Timer",
          r"$type": "number",
          "@unit": "seconds"
        },
        _remove: {r"$name": "Remove", r"$invokable": "write", r"$is": _remove},
        _events: {
          r"$name": "Events",
          AddLocalEventNode.pathName: AddLocalEventNode.def(),
          AddSpecialEventNode.pathName: AddSpecialEventNode.def(),
          FetchSpecialEventsNode.pathName: FetchSpecialEventsNode.def(),
          RemoveSpecialEventNode.pathName: RemoveSpecialEventNode.def()
        },
        FetchEventsNode.pathName: FetchEventsNode.def()
      };

  TimezoneEnv.Location timezone;

  dynamic get defaultValue => attributes[r"@defaultValue"];

  List<Map> storedEvents = [];
  List<Map> specialEvents = [];
  List<Map> weeklyEvents = [];

  Completer<Null> _loadSchedComp;

  final List<Future> _loadQueue;
  ICalendarLocalSchedule(String path, this._loadQueue) : super(path) {
    try {
      timezone = TimezoneEnv.getLocation(getChild("timezone") == null
          ? TimezoneEnv.local.name
          : (getChild("timezone") as SimpleNode).value);
    } catch (e) {
      timezone = TimezoneEnv.UTC;
    }
  }

  Disposable changerDisposable;

  List<ical.StoredEvent> generateStoredEvents() {
    var out = storedEvents
        .map((e) => ical.StoredEvent.decode(e))
        .where((e) => e != null)
        .toList();

    out.addAll(generateSpecialDateEvents());
    out.addAll(generateSpecialDateRangeEvents());
    return out;
  }

  List<ical.StoredEvent> generateSpecialDateRangeEvents() {
    var out = <ical.StoredEvent>[];
    for (Map e in specialEvents) {
      if (e["type"] != "DateRange") continue;

      Map date = e["date"];

      DateTime _getDate(int idx) {
        String yrn = "year${idx}";
        String mtn = "month${idx}";
        String dyn = "day${idx}";
        int year = date[yrn] == null ? TimeUtils.now.year : date[yrn];
        int month = date[mtn];
        int day = date[dyn];

        return new DateTime(
            year, month == null ? 1 : month, day == null ? 1 : day);
      }

      String _getRecurrence(int idx) {
        String r = "YEARLY";
        if (date["month${idx}"] is int) {
          r = "MONTHLY";
        }

        if (date["day${idx}"] is int) {
          r = "DAILY";
        }

        if (date["month${idx}"] is int &&
            date["day${idx}"] is int &&
            date["year${idx}"] is int) {
          r = "DAILY";
        }

        return r;
      }

      DateTime startDate = _getDate(0);
      DateTime endDate = _getDate(1);

      var numDays = endDate.difference(startDate).inDays;
      for (var d = 0; d < numDays; d++) {
        var timeList = e["times"] is List ? e["times"] : [];
        for (Map t in timeList) {
          int start = toInt(t["start"]);
          int end = toInt(t['finish']);
          var val = t["value"];

          if (t["duration"] != null) {
            end = start + toInt(t["duration"]);
          }

          print('Start: $start and End: $end');

          var strt = startDate.add(new Duration(days: d, milliseconds: start));
          if (strt.isAfter(endDate)) break;

          var timeEnd = startDate.add(new Duration(days: d, milliseconds: end));

          var id = e["id"] is String ? e["id"] : generateToken(length: 10);
          // Priority 1 because it's a special event (top priority)
          var oe = new ical.StoredEvent(id, val, new TimeRange(strt, timeEnd),
              {"FREQ": _getRecurrence(0), "UNTIL": formatICalendarTime(timeEnd)}, 1);

          out.add(oe);
        }
      }
    }
    return out;
  }

  List<ical.StoredEvent> generateSpecialDateEvents() {
    var out = <ical.StoredEvent>[];

    for (Map e in specialEvents) {
      if (e["type"] != "Date") continue;

      String  name = e['name'];
      Map d = e["date"];

      DateTime baseDate;
      if (d["year"] == null && d["month"] == null && d["day"] == null) {
        DateTime now = new DateTime.now();
        baseDate = new DateTime(now.year, now.month, now.day - 1);
      } else {
        baseDate = new DateTime(
            d["year"] == null ? 2017 : d["year"],
            d["month"] == null ? 1 : d["month"],
            d["day"] == null ? 1 : d["day"]);
      }
      String type = "YEARLY";

      if (d["month"] is int) {
        type = "MONTHLY";
      }

      if (d["day"] is int) {
        type = "DAILY";
      }

      if (d["month"] is int && d["day"] is int && d["year"] is int) {
        type = "YEARLY";
      }

      var rule = {"FREQ": type};

      if (d["weekday"] is String) {
        rule["BYDAY"] = ical.genericWeekdayToICal(d["weekday"].toString());
        rule["FREQ"] = type = "DAILY";
      }
      // [{"start": 28800000, "finish" : 32400000, "duration": 3600000, "value": 42}]
      List<Map> times = e["times"];
      for (var i = 0; i < times.length; i++) {
        Map t = times[i];
        int start = toInt(t["start"]);
        int finish = toInt(t["finish"]);
        var val = t["value"];

        if (t["duration"] != null) {
          finish = start + toInt(t["duration"]);
        }

        String id;
        if (name != null && name.isNotEmpty) {
          id = '$name-${i + 1}';
        } else {
          id = generateToken(length: 30);
        }
        // Priority 1 because it's a special event (top priority)
        var event = new ical.StoredEvent(id, val,
            new TimeRange(baseDate.add(new Duration(milliseconds: start)),
                baseDate.add(new Duration(milliseconds: finish))),
            rule, 1);

        event.id = e["id"] is String ? e["id"] : generateToken();

        out.add(event);
      }
    }

    return out;
  }

  void _addMissing(String path, Map<String, dynamic> map) {
    var nd = provider.getNode(path);
    if (nd != null) return;

    provider.addNode(path, map);
  }

  @override
  onCreated() {
    _addMissing('$path/$_current',
        {r'$name': 'Current Value', r'$type': 'dynamic'});
    _addMissing('$path/$_next', {r'$name': 'Next Value', r'$type': 'dynamic'});
    _addMissing('$path/$_next_ts',
        {r"$name": "Next Value Timestamp", r"$type": "dynamic"});
    _addMissing('$path/$_stc', {
        r"$name": "Next Value Timer",
        r"$type": "number",
        "@unit": "seconds"
    });
    _addMissing('$path/$_remove',
        {r"$name": "Remove", r"$invokable": "write", r"$is": _remove});
    _addMissing('$path/${FetchEventsNode.pathName}', FetchEventsNode.def());
    _addMissing('$path/$_events', {
      r"$name": "Events",
      AddLocalEventNode.pathName: AddLocalEventNode.def(),
      AddSpecialEventNode.pathName: AddSpecialEventNode.def(),
      FetchSpecialEventsNode.pathName: FetchSpecialEventsNode.def(),
      RemoveSpecialEventNode.pathName: RemoveSpecialEventNode.def()
    });

    if (attributes["@events"] is List) {
      storedEvents.clear();
      for (var element in attributes["@events"]) {
        if (element is Map) {
          storedEvents.add(element);
        }
      }
    }

    if (attributes["@specialEvents"] is List) {
      specialEvents.clear();
      for (var element in attributes["@specialEvents"]) {
        if (element is Map) {
          specialEvents.add(element);
        }
      }
    }

    if (attributes["@weeklyEvents"] is List) {
      weeklyEvents.clear();
      for (var element in attributes["@weeklyEvents"]) {
        if (element is Map) {
          weeklyEvents.add(element);
        }
      }
    }

    TimezoneNode nd = provider.getNode("$path/${TimezoneNode.pathName}");
    if (nd == null) {
      nd = provider.addNode("$path/${TimezoneNode.pathName}",
          TimezoneNode.def(TimezoneEnv.local.name));
      nd.schedule = this;
    } else {
      nd.schedule = this;
      nd.onSetValue(nd.value);
    }

    nd.schedule = this;

    var future = loadSchedule();

    if (_loadQueue != null) {
      _loadQueue.add(future);
    }
  }

  bool isLoadingSchedule = false;
  String generatedCalendar;

  Future loadSchedule([bool isUpdate = false]) async {
    await runZoned(() async {
      await _loadSchedule(isUpdate);
    }, zoneValues: {
      "mock.time": () {
        return new DateTime.now();
      }
    });
  }

  Future _loadSchedule([bool isUpdate = false]) async {
    if (isLoadingSchedule) {
      return _loadSchedComp.future;
    }

    _loadSchedComp = new Completer<Null>();
    isLoadingSchedule = true;

    logger.fine("Schedule '${displayName}': Loading Schedule");

    provider.removeNode("$path/error");
    var evntNode = provider.getNode('$path/$_events');

    if (evntNode != null) {
      evntNode.children.keys.toList().forEach((x) {
        // TODO: (mbutler) will this ever be called? children are tokens not ints.
        if (int.parse(x, onError: (source) => null) != null) {
          var n = provider.getNode("$path/$_events/$x");
          if (n is EventNode) {
            n.flagged = true;
          }

          if (!isUpdate) {
            provider.removeNode("$path/$_events/$x");
          }
        }
      });
    }

    // Wait so that the removing of those events can be flushed.
    await new Future.delayed(const Duration(milliseconds: 2));

    try {
      ical.CalendarObject object;

      List<ical.StoredEvent> loadedEvents = generateStoredEvents();

      var data = await ical.generateCalendar(displayName, timezone);
      var tokens = ical.tokenizeCalendar(data);
      object = ical.parseCalendarObjects(tokens);
      rootCalendarObject = object;
      if (object.properties["VEVENT"] == null) {
        object.properties["VEVENT"] = [];
      }

      // Used just as an alias to the the list (pass by reference)
      List<ical.CalendarObject> objVevents = object.properties["VEVENT"];
      for (var n in loadedEvents) {
        if (n == null) continue;

        var e = n.toCalendarObject();
        e.parent = object;
        objVevents.add(n.toCalendarObject());
      }

      StringBuffer buff = new StringBuffer();
      ical.serializeCalendar(object, buff);
      generatedCalendar = buff.toString();

      var events = ical.loadEvents(generatedCalendar, timezone);
      icalProvider = new ical.ICalendarProvider(
          events.map((x) => new ical.EventInstance(x)).toList());

      state = new ValueCalendarState(icalProvider);
      state.defaultValue = new ValueAtTime.forDefault(defaultValue);

      ValueAtTime next;
      DateTime nextTimestamp;

      if (changerDisposable != null) {
        changerDisposable.dispose();
      }

      if (untilTimer != null && untilTimer.isActive) untilTimer.cancel();

      var setNextEvent = (ValueAtTime v) {
        provider.updateValue("${path}/$_current", v.value);
        next = state.getNext();
        if (next != null) {
          provider.updateValue("${path}/$_next", next.value);
          provider.updateValue("${path}/$_next_ts", next.time.toIso8601String());
          nextTimestamp = next.time;
        } else {
          provider.updateValue("${path}/$_next", null);
          provider.updateValue("${path}/$_next_ts", null);
          nextTimestamp = null;
        }
      };

      var firstCurrent = state.getCurrent();

      var cur = provider.getNode('$path/$_current') as SimpleNode;
      if (cur == null) {
        cur = provider.addNode('$path/$_current',
          {r'$name': 'Current Value', r'$type': 'dynamic'});
      }

      cur.updateValue(firstCurrent?.value ?? defaultValue);

      changerDisposable = state.listen(setNextEvent);

      untilTimer = new Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (nextTimestamp != null) {
          Duration duration = nextTimestamp.difference(TimeUtils.now);

          if (duration.isNegative) {
            var msg = "It's ${TimeUtils.now}, but ${nextTimestamp}"
                " is the next event for ${path}";

            logger.fine(msg);

            if (state.defaultValue != null) {
              setNextEvent(state.defaultValue);
            }
            return;
          } else {
            duration = duration.abs();
          }

          provider.updateValue("${path}/stc", duration.inSeconds);
        } else {
          provider.updateValue("${path}/stc", 0);
        }
      });

      var eventList = icalProvider.listEvents();

      var i = 0;
      for (var event in eventList) {
        i++;

        var eId = event.uuid ?? i.toString();
        var pid = NodeNamer.createName(eId);

        var rp = "$path/events/$pid";
        addOrUpdateNode(provider, rp, EventNode.def(event, i));
        SimpleNode eventNode = provider.getNode(rp);
        eventNode.updateList(r"$is");
      }
    } catch (e, stack) {
      provider.addNode("${path}/error",
          {r"$name": "Error", r"$type": "string", "?value": e.toString()});

      logger.warning("Schedule '${displayName}' has an error.", e, stack);
    }

    _loadSchedComp.complete(null);
    isLoadingSchedule = false;

    return _loadSchedComp.future;
//    link.save();
  }

  @override
  onRemoving() {
    if (changerDisposable != null) {
      changerDisposable.dispose();
    }

    if (untilTimer != null) {
      untilTimer.cancel();
    }

    if (httpTimer != null) {
      httpTimer.dispose();
    }
  }

  @override
  Map save() {
    var map = {
      r"$is": configs[r"$is"],
      r"$name": configs[r"$name"],
      "@url": attributes["@url"],
      "@defaultValue": attributes["@defaultValue"],
    };

    var curMap = (getChild(_current) as SimpleNode)?.save();
    if (curMap != null && curMap.isNotEmpty) map[_current] = curMap;

    if (attributes["@calendar"] != null) {
      map["@calendar"] = attributes["@calendar"];
    }

    map["@events"] = storedEvents;
    map["@specialEvents"] = specialEvents;
    map["@weeklyEvents"] = weeklyEvents;

    map["timezone"] = (getChild("timezone") as SimpleNode).save();

    return map;
  }

  ical.CalendarObject rootCalendarObject;
  ValueCalendarState state;
  ical.ICalendarProvider icalProvider;
  Timer untilTimer;
  Disposable httpTimer;

  String calculateTag() {
    var json = const JsonEncoder().convert(storedEvents);
    return sha256.convert(const Utf8Encoder().convert(json)).toString();
  }
}

class AddLocalEventNode extends SimpleNode {
  static const String isType = 'addLocalEvent';
  static const String pathName = 'addEvent';

  // Params
  static const String _name = 'name';
  static const String _time = 'time';
  static const String _value = 'value';
  static const String _rule = 'rule';

  static Map<String, dynamic> def() => {
        r"$name": "Add Event",
        r"$is": isType,
        r"$params": [
          {"name": _name, "type": "string", "placeholder": "Turn on Light"},
          {"name": _time, "type": "string", "editor": "daterange"},
          {"name": _value, "type": "dynamic", "description": "Event Value"},
          {"name": _rule, "type": "string", "placeholder": "FREQ=DAILY"}
        ],
        r"$invokable": "write"
      };

  final LinkProvider _link;
  AddLocalEventNode(String path, this._link) : super(path);

  @override
  Future onInvoke(Map<String, dynamic> params) async {
    var name = params[_name];
    var timeRangeString = params[_time];
    var value = parseInputValue(params[_value]);
    var ruleString = params[_rule];

    if (name is! String || name.isEmpty) {
      throw new Exception("Invalid Event Name");
    }

    if (timeRangeString is! String) {
      throw new Exception("Invalid Event Times");
    }

    DateTime start;
    DateTime end;
    Map rule;

    var parts = timeRangeString.split("/");
    start = DateTime.parse(parts[0]);
    end = DateTime.parse(parts[1]);
    TimeRange range = new TimeRange(start, end);

    if (ruleString != null && ruleString.toString().isNotEmpty) {
      rule = ical.tokenizePropertyList(ruleString);
    }

    var event = new ical.StoredEvent(name, value, range);

    if (rule != null && rule.isNotEmpty) {
      event.rule = rule;
    }

    var p = new Path(path);
    ICalendarLocalSchedule schedule = _link.getNode(p.parent.parent.path);

    schedule.storedEvents.removeWhere((x) => x["name"] == name);
    schedule.storedEvents.add(event.encode());

    _link.save();
    await schedule.loadSchedule();
  }
}

class EditLocalEventNode extends SimpleNode {
  static const String isType = 'editLocalEvent';
  static const String pathName = 'edit';

  // Params
  static const String _name = 'name';
  static const String _time = 'time';
  static const String _value = 'value';
  static const String _rule = 'rule';

  static Map<String, dynamic> def(EventDescription event, String rules) => {
        r"$name": "Edit",
        r"$is": isType,
        r"$invokable": "write",
        r"$params": [
          {"name": _name, "type": "string", "default": event.name},
          {
            "name": _time,
            "type": "string",
            "editor": "daterange",
            "default": "${event.start}/${event.end}"
          },
          {"name": _value, "type": "dynamic", "default": event.value},
          {
            "name": _rule,
            "type": "string",
            "placeholder": "FREQ=DAILY",
            "default": rules
          }
        ]
      };

  EditLocalEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params[_name];
    var timeRangeString = params[_time];
    var ruleString = params[_rule];
    var val = params[_value];

    var p = new Path(path);

    ICalendarLocalSchedule schedule =
        provider.getNode(p.parent.parent.parent.path);

    String eventId = p.parent.name;

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

    if (eventId != null) {
      Map m = schedule.storedEvents.firstWhere((x) => x["id"] == eventId);
      int myidx = schedule.storedEvents.indexOf(m);

      if (name is String) m["name"] = name;
      if (start is DateTime) m["start"] = start.toIso8601String();
      if (end is DateTime) m["end"] = end.toIso8601String();
      if (rule is Map) m["rule"] = rule;

      if (params.containsKey("value")) m["value"] = parseInputValue(val);

      if (myidx >= 0) {
        schedule.storedEvents[myidx] = m;
      } else {
        schedule.storedEvents.add(m);
      }

      await schedule.loadSchedule(true);
    } else {
      throw new Exception("Failed to resolve event.");
    }
  }
}
