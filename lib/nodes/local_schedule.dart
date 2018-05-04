import 'dart:async';
import 'dart:convert';

import 'package:dslink/dslink.dart';
import 'package:dslink/utils.dart';
import 'package:dslink/nodes.dart' show NodeNamer;
import 'package:timezone/src/location.dart';
import "package:timezone/src/env.dart" as TimezoneEnv;
import "package:crypto/crypto.dart";

import 'common.dart';
import 'local_event.dart';
import 'event.dart';
import 'timezone.dart';
import "../ical.dart" as ical;
import "../calendar.dart";
import '../utils.dart';
import '../src/loading_queue.dart';

class AddICalLocalScheduleNode extends SimpleNode {
  static const String pathName = 'addiCalLocalSchedule';
  static const String isType = 'addiCalLocalSchedule';
  static const String _name = 'name';
  static const String _defaultValue = 'defaultValue';

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

  final LinkProvider link;
  AddICalLocalScheduleNode(String path, this.link) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    String name = params[_name];
    dynamic defaultValue = params[_defaultValue];

    defaultValue = parseInputValue(defaultValue);

    var encoded = NodeNamer.createName(name);
    provider.addNode("/$encoded",
        ICalendarLocalScheduleImpl.def(name, defaultValue));

    link.save();
  }
}

class ICalendarLocalScheduleImpl extends SimpleNode implements ICalendarLocalSchedule {
  static const String isType = 'iCalLocalSchedule';
  static const String aDefaultValue = '@defaultValue';
  static const String aStoredEvents = '@events';
  static const String aSpecialEvents = '@specialEvents';
  static const String aWeeklyEvents = '@weeklyEvents';

  static const String _current = 'current';
  static const String _next = 'next';
  static const String _nextTs = 'next_ts';

  static Map<String, dynamic> def(String name, dynamic defaultValue) => {
    r'$is': isType,
    r"$name": name,
    _current: {
      r"$name": "Current Value",
      r"$type": "dynamic",
      r'?value': ''
    },
    _next: {
      r"$name": "Next Value",
      r"$type": "dynamic",
      r'?value': ''
    },
    _nextTs: {

    },
    aDefaultValue: defaultValue,
    aStoredEvents: [],
    aSpecialEvents: [],
    aWeeklyEvents: []
  };

  dynamic get defaultValue => attributes[aDefaultValue];

  Location timezone;
  List<Map> storedEvents = [];
  List<Map> specialEvents = [];
  List<Map> weeklyEvents = [];

  ical.CalendarObject rootCalendarObject;
  ValueCalendarState state;
  ical.ICalendarProvider icalProvider;
  Timer untilTimer;
  Disposable httpTimer;

  bool isLoadingSchedule = false;
  String generatedCalendar;

  final LinkProvider link;
  final LoadingQueue loadQueue;
  ICalendarLocalScheduleImpl(String path, this.link, this.loadQueue) : super(path) {
    try {
      timezone = TimezoneEnv.getLocation(
          getChild("timezone") == null ?
          TimezoneEnv.local.name :
          (getChild("timezone") as SimpleNode).value
      );
    } catch (e) {
      timezone = TimezoneEnv.UTC;
    }
  }

  Disposable changerDisposable;

  Future<Null> addStoredEvent(ical.StoredEvent event) async {
    storedEvents.removeWhere((x) => x["name"] == event.name);
    storedEvents.add(event.encode());
    await loadSchedule();
  }

  Future updateStoredEvent(String eventId, Map eventData) async {
    int index = -1;
    for (var i = 0; i < storedEvents.length; i++) {
      if (storedEvents[i]['id'] == eventId) {
        index = i;
        break;
      }
    }

    if (index == -1) {
      eventData['id'] = eventId;
      storedEvents.add(eventData);
    } else {
      storedEvents[index]
          ..['name'] = eventData['name']
          ..['start'] = eventData['start']
          ..['end'] = eventData['end']
          ..['rule'] = eventData['rule']
          ..['value'] = eventData['value'];
    }

    await loadSchedule(true);
  }

  void removeStoredEvent(String name) {
    storedEvents.removeWhere((x) => x["name"] == name);
    loadSchedule();
  }

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
      if (e["type"] != "Date-Range") {
        continue;
      }

      Map date = e["date"];

      DateTime _getDate(int idx) {
        String yrn = "year${idx}";
        String mtn = "month${idx}";
        String dyn = "day${idx}";
        int year = date[yrn] == null ? TimeUtils.now.year : date[yrn];
        int month = date[mtn];
        int day = date[dyn];

        return new DateTime(
            year,
            month == null ? 1 : month,
            day == null ? 1 : day
        );
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
          r = "YEARLY";
        }

        return r;
      }

      DateTime startDate = _getDate(0);
      DateTime endDate = _getDate(1);

      var timeList = e["times"] is List ? e["times"] : [];
      for (Map t in timeList) {
        int start = toInt(t["start"]);
        int end = toInt(t["finish"]);
        var val = t["value"];

        if (end == null && t["duration"] != null) {
          end = start + toInt(t["duration"]);
        }

        var strt = startDate.add(new Duration(milliseconds: start));
        var nd = endDate.add(new Duration(milliseconds: end));

        var id = e["id"] is String ? e["id"] : generateToken(length: 10);
        var oe = new ical.StoredEvent(
            id,
            val,
            new TimeRange(strt, nd),
            {
              "FREQ": _getRecurrence(0),
              "UNTIL": formatICalendarTime(nd)
            }
        );

        out.add(oe);
      }
    }
    return out;
  }

  List<ical.StoredEvent> generateSpecialDateEvents() {
    var out = <ical.StoredEvent>[];

    for (Map e in specialEvents) {
      if (e["type"] != "Date") {
        continue;
      }

      Map d = e["date"];

      DateTime baseDate;
      if (d["year"] == null && d["month"] == null && d["day"] == null) {
        DateTime now = new DateTime.now();
        baseDate = new DateTime(now.year, now.month, now.day - 1);
      } else {
        baseDate = new DateTime(
            d["year"] == null ? 2017 : d["year"],
            d["month"] == null ? 1 : d["month"],
            d["day"] == null ? 1 : d["day"]
        );
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

      var rule = {
        "FREQ": type
      };

      if (d["weekday"] is String) {
        rule["BYDAY"] = ical.genericWeekdayToICal(d["weekday"].toString());
        rule["FREQ"] = type = "DAILY";
      }

      List<Map> times = e["times"];
      for (Map t in times) {
        int start = toInt(t["start"]);
        int finish = toInt(t["finish"]);
        var val = t["value"];

        if (t["duration"] != null) {
          finish = start + toInt(t["duration"]);
        }

        var id = generateToken(length: 30);
        var event = new ical.StoredEvent(
            id,
            val,
            new TimeRange(
                baseDate.add(new Duration(milliseconds: start)),
                baseDate.add(new Duration(milliseconds: finish))
            ),
            rule
        );

        event.id = e["id"] is String ? e["id"] : generateToken();

        out.add(event);
      }
    }

    return out;
  }

  @override
  onCreated() {
    if (attributes[aStoredEvents] is List) {
      storedEvents.clear();
      for (var element in attributes[aStoredEvents]) {
        if (element is Map) {
          storedEvents.add(element);
        }
      }
    }

    if (attributes[aSpecialEvents] is List) {
      specialEvents.clear();
      for (var element in attributes[aSpecialEvents]) {
        if (element is Map) {
          specialEvents.add(element);
        }
      }
    }

    if (attributes[aWeeklyEvents] is List) {
      weeklyEvents.clear();
      for (var element in attributes[aWeeklyEvents]) {
        if (element is Map) {
          weeklyEvents.add(element);
        }
      }
    }

    TimezoneNode nd = provider.getNode("$path/${TimezoneNode.pathName}");
    if (nd == null) {
      nd = provider.addNode("$path/${TimezoneNode.pathName}",
          TimezoneNode.def(TimezoneEnv.local.name)) as TimezoneNode;
      nd.schedule = this;
    } else {
      nd.schedule = this;
      nd.onSetValue(nd.value);
    }

    link.addNode("${path}/fetchEvents", {
      r"$name": "Fetch Events",
      r"$invokable": "read",
      r"$is": "fetchEvents",
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
    });

    link.addNode("${path}/next_ts", {
      r"$name": "Next Value Timestamp",
      r"$type": "dynamic"
    });

    link.addNode("${path}/stc", {
      r"$name": "Next Value Timer",
      r"$type": "number",
      "@unit": "seconds"
    });

    link.addNode("${path}/events", {
      r"$name": "Events",
      AddLocalEventNode.pathName: AddLocalEventNode.def(),
      "addSpecialEvent": {
        r"$name": "Add Special Event",
        r"$is": "addLocalSpecialEvent",
        r"$params": [
          {
            "name": "Name",
            "type": "string"
          },
          {
            "name": "Type",
            "type": "enum[Date,DateRange]"
          },
          {
            "name": "Date",
            "type": "string",
            "editor": "textarea"
          },
          {
            "name": "Times",
            "type": "string",
            "editor": "textarea"
          },
          {
            "name": "ReplacementId",
            "type": "string"
          }
        ],
        r"$columns": [
          {
            "name": "CreatedId",
            "type": "string"
          }
        ],
        r"$invokable": "write",
        r"$actionGroup": "Advanced"
      },
      "fetchSpecialEvents": {
        r"$name": "Fetch Special Events",
        r"$is": "fetchSpecialEvents",
        r"$columns": [
          {
            "name": "Id",
            "type": "string"
          },
          {
            "name": "Name",
            "type": "string"
          },
          {
            "name": "Type",
            "type": "string"
          },
          {
            "name": "Date",
            "type": "string"
          },
          {
            "name": "Times",
            "type": "string"
          }
        ],
        r"$result": "table",
        r"$invokable": "read",
        r"$actionGroup": "Advanced"
      },
      "removeSpecialEvent": {
        r"$name": "Remove Special Event",
        r"$invokable": "write",
        r"$params": [
          {
            "name": "Id",
            "type": "string"
          }
        ],
        r"$actionGroup": "Advanced",
        r"$is": "removeSpecialEvent"
      }
    });

    link.addNode("${path}/remove", {
      r"$name": "Remove",
      r"$invokable": "write",
      r"$is": "remove"
    });

    var future = loadSchedule();

    loadQueue.add(future);
  }

  loadSchedule([bool isUpdate = false]) async {
    await runZoned(() async {
      await _loadSchedule(isUpdate);
      updateList(aStoredEvents);
      updateList(aSpecialEvents);
      updateList(aWeeklyEvents);
    }, zoneValues: {
      "mock.time": () {
        return new DateTime.now();
      }
    });
  }

  _loadSchedule([bool isUpdate = false]) async {
    if (isLoadingSchedule) {
      while (isLoadingSchedule) {
        await new Future.delayed(const Duration(milliseconds: 50));
      }
    }

    isLoadingSchedule = true;
    logger.fine("Schedule '${displayName}': Loading Schedule");

    try {
      link.removeNode("${path}/error");
      link.getNode("${path}/events").children.keys.toList().forEach((x) {
        if (int.parse(x, onError: (source) => null) != null) {
          var n = link.getNode("${path}/events/${x}");
          if (n is EventNode) {
            n.flagged = true;
          }

          if (!isUpdate) {
            link.removeNode("${path}/events/${x}");
          }
        }
      });

      // Wait so that the removing of those events can be flushed.
      await new Future.delayed(const Duration(milliseconds: 2));

      ical.CalendarObject object;

      {
        List<ical.StoredEvent> loadedEvents = generateStoredEvents();

        var data = await ical.generateCalendar(displayName, timezone);
        var tokens = ical.tokenizeCalendar(data);
        object = ical.parseCalendarObjects(tokens);
        rootCalendarObject = object;
        if (object.properties["VEVENT"] == null) {
          object.properties["VEVENT"] = [];
        }
        List<ical.CalendarObject> fakeEventObjects = object.properties["VEVENT"];
        for (var n in loadedEvents) {
          if (n == null) {
            continue;
          }
          var e = n.toCalendarObject();
          e.parent = object;
          fakeEventObjects.add(n.toCalendarObject());
        }
      }

      StringBuffer buff = new StringBuffer();
      ical.serializeCalendar(object, buff);
      generatedCalendar = buff.toString();

      var events = ical.loadEvents(generatedCalendar, timezone);
      icalProvider = new ical.ICalendarProvider(
          events.map((x) => new ical.EventInstance(x)).toList()
      );

      state = new ValueCalendarState(icalProvider);
      state.defaultValue = new ValueAtTime.forDefault(defaultValue);

      ValueAtTime next;
      DateTime nextTimestamp;

      if (changerDisposable != null) {
        changerDisposable.dispose();
      }

      if (untilTimer != null) {
        untilTimer.cancel();
      }

      var setNextEvent = (ValueAtTime v) {
        link.val("$path/$_current", v.value);
        next = state.getNext();
        if (next != null) {
          link.val("${path}/next", next.value);
          link.val("${path}/next_ts", next.time.toIso8601String());
          nextTimestamp = next.time;
        } else {
          link.val("${path}/next", null);
          link.val("${path}/next_ts", null);
          nextTimestamp = null;
        }
      };

      var firstCurrent = state.getCurrent();

      if (firstCurrent != null) {
        provider.updateValue('$path/$_current', firstCurrent.value);
      } else {
        provider.updateValue("$path/$_current", defaultValue);
      }

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

          link.val("${path}/stc", duration.inSeconds);
        } else {
          link.val("${path}/stc", 0);
        }
      });

      var eventList = icalProvider.listEvents();

      var i = 0;
      for (var event in eventList) {
        i++;

        var map = event.asNode(i);
        var pid = NodeNamer.createName(map["id"]["?value"]);

        var rp = "${path}/events/${pid}";
        addOrUpdateNode(link.provider, rp, map);
        SimpleNode eventNode = link.getNode(rp);
        eventNode.updateList(r"$is");

        if (event.rule == null) {
          event.rule = {};
        }

        String ruleString = "";
        for (var key in event.rule.keys) {
          var val = event.rule[key];

          ruleString += "${key}=${val};";
        }

        if (ruleString.endsWith(";")) {
          ruleString = ruleString.substring(0, ruleString.length - 1);
        }

        addOrUpdateNode(link.provider, "${rp}/edit", EditLocalEventNode.def(event, ruleString));
      }
    } catch (e, stack) {
      link.addNode("${path}/error", {
        r"$name": "Error",
        r"$type": "string",
        "?value": e.toString()
      });

      logger.warning("Schedule '${displayName}' has an error.", e, stack);
    }

    isLoadingSchedule = false;

    link.save();
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
      "@defaultValue": attributes["@defaultValue"]
    };

    if (attributes["@calendar"] != null) {
      map["@calendar"] = attributes["@calendar"];
    }

    map["@events"] = storedEvents;
    map["@specialEvents"] = specialEvents;
    map["@weeklyEvents"] = weeklyEvents;

    map[_current] = (getChild(_current) as SimpleNode).save();
    map[_next] = (getChild(_next) as SimpleNode).save();
    map["timezone"] = (getChild("timezone") as SimpleNode).save();

    return map;
  }

  String calculateTag() {
    var json = const JsonEncoder().convert(storedEvents);
    return sha256.convert(const Utf8Encoder().convert(json)).toString();
  }
}