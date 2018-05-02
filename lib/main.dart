library dslink.schedule.main;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import "package:dslink_schedule/ical.dart" as ical;
import "package:dslink_schedule/calendar.dart";

import "package:dslink_schedule/tz.dart";
import "package:dslink_schedule/utils.dart";

import "package:http/http.dart" as http;

import "package:timezone/src/env.dart" as TimezoneEnv;
import 'package:timezone/standalone.dart';

import "package:path/path.dart" as pathlib;

import 'package:timezone/src/location.dart';
import "package:xml/xml.dart" as XML;

import "package:crypto/crypto.dart";

part "src/http.dart";

LinkProvider link;
http.Client httpClient = new http.Client();
//SimpleNodeProvider provider;

main(List<String> args) async {
  String basePath = Directory.current.path;

  link = new LinkProvider(args, "Schedule-", profiles: {
    "addiCalRemoteSchedule": (String path) => new AddICalRemoteScheduleNode(path),
    AddICalLocalScheduleNode.isType: (String path) => new AddICalLocalScheduleNode(path, link),
    "iCalRemoteSchedule": (String path) => new ICalendarRemoteSchedule(path),
    ICalendarLocalSchedule.isType: (String path) => new ICalendarLocalSchedule(path),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider as MutableNodeProvider, onDelete: () {
      link.save();
    }),
    "event": (String path) => new EventNode(path),
    AddLocalEventNode.isType: (String path) => new AddLocalEventNode(path),
    "httpPort": (String path) => new HttpPortNode(path),
    "editLocalEvent": (String path) => new EditLocalEventNode(path),
    "fetchEvents": (String path) => new FetchEventsNode(path),
    "fetchEventsForEvent": (String path) => new FetchEventsForEventNode(path),
    "addLocalSpecialEvent": (String path) => new AddSpecialEventNode(path),
    "fetchSpecialEvents": (String path) => new FetchSpecialEventsNode(path),
    "removeSpecialEvent": (String path) => new RemoveSpecialEventNode(path),
    TimezoneNode.isType: (String path) => new TimezoneNode(path)
  }, autoInitialize: false);

  link.configure(optionsHandler: (opts) {
    if (opts["base-path"] != null) {
      basePath = opts["base-path"];
    }
  });

  try {
//    String tzPath = pathlib.join(
//      basePath,
//      'packages',
//      'timezone',
//      'data',
//      TimezoneEnv.tzDataDefaultFilename
//    );
//
//    File file = new File(tzPath);
//    List<int> bytes = await file.readAsBytes();
//    await TimezoneEnv.initializeDatabase(bytes);
  await initializeTimeZone();
  } catch (e, stack) {
    logger.warning("Failed to load timezone data", e, stack);
  }

  setLocalLocation(await findTimezoneOnSystem());

  loadQueue = [];

  link.init();

  var provider = link.provider as SimpleNodeProvider;

  link.addNode("/addiCalRemoteSchedule", {
    r"$is": "addiCalRemoteSchedule",
    r"$name": "Add Remote Schedule",
    r"$params": [
      {
        "name": "name",
        "type": "string",
        "placeholder": "Light Schedule",
        "description": "Name of the Schedule"
      },
      {
        "name": "url",
        "type": "string",
        "placeholder": "http://my.calendar.host/calendar.ics",
        "description": "URL to the iCalendar File"
      },
      {
        "name": "defaultValue",
        "type": "dynamic",
        "description": "Default Value for Schedule",
        "default": 0
      }
    ],
    r"$invokable": "write"
  });

  if (!provider.nodes.containsKey("/httpPort")) {
    link.addNode("/httpPort", {
      r"$name": "HTTP Port",
      r"$type": "int",
      r"$writable": "write",
      r"$is": "httpPort",
      "?value": -1
    });
  }

  var portValue = link.val("/httpPort");
  await rebindHttpServer(portValue is String ? int.parse(portValue) : portValue);

  link.addNode("/${AddICalLocalScheduleNode.pathName}",
      AddICalLocalScheduleNode.def());

  await Future.wait(loadQueue);
  loadQueue = null;

  link.connect();
}

class AddICalRemoteScheduleNode extends SimpleNode {
  AddICalRemoteScheduleNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    String name = params["name"];
    String url = params["url"];
    dynamic defaultValue = params["defaultValue"];

    defaultValue = parseInputValue(defaultValue);

    var rawName = NodeNamer.createName(name);
    link.addNode("/${rawName}", {
      r"$is": "iCalRemoteSchedule",
      r"$name": name,
      "@url": url,
      "@defaultValue": defaultValue
    });

    link.save();
  }
}

class EventNode extends SimpleNode {
  EventDescription description;
  bool flagged = false;

  EventNode(String path) : super(path);

  @override
  onRemoving() {
    var p = new Path(path);
    var node = link.getNode(p.parent.parent.path);
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

class EditLocalEventNode extends SimpleNode {
  EditLocalEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params["name"];
    var timeRangeString = params["time"];
    var ruleString = params["rule"];
    var val = params["value"];

    var p = new Path(path);

    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.parent.path);

    String eventId = p.parent.name;

    DateTime start;
    DateTime end;
    Map rule;

    {
      if (timeRangeString is String) {
        var parts = timeRangeString.split("/");
        start = DateTime.parse(parts[0]);
        end = DateTime.parse(parts[1]);
      }
    }

    if (ruleString is String && ruleString.isNotEmpty) {
      rule = ical.tokenizePropertyList(ruleString);
    }

    if (eventId != null) {
      Map m = schedule.storedEvents.firstWhere((x) => x["id"] == eventId);
      int myidx = schedule.storedEvents.indexOf(m);

      if (name is String) {
        m["name"] = name;
      }

      if (start is DateTime) {
        m["start"] = start.toIso8601String();
      }

      if (end is DateTime) {
        m["end"] = end.toIso8601String();
      }

      if (rule is Map) {
        m["rule"] = rule;
      }

      if (params.containsKey("value")) {
        m["value"] = parseInputValue(val);
      }

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
    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.path);

    schedule.storedEvents.removeWhere((x) => x[_name] == name);
    schedule.storedEvents.add(event.encode());
    await schedule.loadSchedule();
  }
}

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

    var rawName = NodeNamer.createName(name);
    link.addNode("/$rawName", ICalendarLocalSchedule.def(name, defaultValue));

    link.save();
  }
}

List<Future> loadQueue;

class ICalendarRemoteSchedule extends SimpleNode {
  dynamic get defaultValue => attributes[r"@defaultValue"];
  String get url => attributes["@url"];
  String get backupCalendar => attributes["@calendar"];

  ICalendarRemoteSchedule(String path) : super(path);

  Disposable changerDisposable;

  @override
  onCreated() {
    link.addNode("${path}/current", {
      r"$name": "Current Value",
      r"$type": "dynamic"
    });

    link.addNode("${path}/next", {
      r"$name": "Next Value",
      r"$type": "dynamic"
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
      r"$name": "Events"
    });

    link.addNode("${path}/remove", {
      r"$name": "Remove",
      r"$invokable": "write",
      r"$is": "remove"
    });

    var future = loadSchedule();

    if (loadQueue != null) {
      loadQueue.add(future);
    }
  }

  String _lastContent;

  loadSchedule([String content]) async {
    logger.fine("Schedule '${displayName}': Loading Schedule");

    try {
      if (content == null) {
        try {
          var response = await httpClient.get(url);
          if (response.statusCode != 200) {
            throw new Exception("Failed to fetch schedule: Status Code was ${response.statusCode}");
          }
          content = response.body;
        } catch (e) {
          if (backupCalendar != null) {
            content = backupCalendar;
          } else {
            rethrow;
          }
        }
      }

      link.removeNode("${path}/error");
      link.getNode("${path}/events").children.keys.toList().forEach((x) {
        var n = link.getNode("${path}/events/${x}");
        if (n is EventNode) {
          n.flagged = true;
        }
        link.removeNode("${path}/events/${x}");
      });

      // Wait so that the removing of those events can be flushed.
      await new Future.delayed(const Duration(milliseconds: 4));

      var events = ical.loadEvents(content, TimezoneEnv.local);
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

      var func = (ValueAtTime v) {
        link.val("${path}/current", v.value);
        next = state.getNext();
        if (next != null) {
          link.val("${path}/next", next.value);
          link.val("${path}/next_ts", next.time.toIso8601String());
          nextTimestamp = next.time;
        } else {
          link.val("${path}/next", defaultValue);
          link.val("${path}/next_ts", v.endsAt.toIso8601String());
          nextTimestamp = v.endsAt;
        }
      };

      changerDisposable = state.listen(func);

      untilTimer = new Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (nextTimestamp != null) {
          Duration duration = nextTimestamp.difference(new DateTime.now());
          if (duration.isNegative) {
            if (state.defaultValue != null) {
              func(state.defaultValue);
            }
            return;
          } else {
            duration = duration.abs();
          }
          link.val("${path}/stc", duration.inSeconds);
        }
      });

      var eventList = icalProvider.listEvents();

      var i = 0;
      for (var event in eventList) {
        i++;

        var map = event.asNode(i);

        SimpleNode eventNode = link.addNode("${path}/events/${i}", map);
        eventNode.updateList(r"$name");
      }

      _lastContent = content;

      attributes["@calendar"] = content;
      await link.saveAsync();

      if (httpTimer == null) {
        httpTimer = Scheduler.safeEvery(new Interval.forSeconds(10), () async {
          try {
            logger.finest("Schedule '${displayName}': Checking for Schedule Update");

            var response = await httpClient.get(url);

            if (response.statusCode != 200) {
              logger.fine("Schedule '${displayName}': Checking for Schedule Update Failed (Status Code: ${response.statusCode})");
              return;
            }

            var content = response.body;

            if (_lastContent != content) {
              var lastLines = _lastContent.split("\n");
              var lines = content.split("\n");
              lastLines.removeWhere((x) => x.startsWith("DTSTAMP:"));
              lines.removeWhere((x) => x.startsWith("DTSTAMP:"));
              if (lastLines.join("\n") != lines.join("\n")) {
                logger.info("Schedule '${displayName}': Updating Schedule");
                await loadSchedule(content);
              }
            } else {
              logger.fine("Schedule '${displayName}': Schedule Up-To-Date");
            }
          } catch (e) {
            logger.warning("Failed to check for schedule update for '${displayName}': ${e}");
          }
        });
      }
    } catch (e, stack) {
      link.addNode("${path}/error", {
        r"$name": "Error",
        r"$type": "string",
        "?value": e.toString()
      });

      logger.warning("Schedule '${displayName}' has an error.", e, stack);
    }
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

    return map;
  }

  ValueCalendarState state;
  ical.ICalendarProvider icalProvider;
  Timer untilTimer;
  Disposable httpTimer;
}

class ICalendarLocalSchedule extends SimpleNode {
  static const String isType = 'iCalLocalSchedule';
  static const String aDefaultValue = '@defaultValue';
  static const String aStoredEvents = '@events';
  static const String aSpecialEvents = '@specialEvents';
  static const String aWeeklyEvents = '@weeklyEvents';

  static Map<String, dynamic> def(String name, dynamic defaultValue) => {
    r'$is': isType,
    r"$name": name,
    aDefaultValue: defaultValue,
    aStoredEvents: [],
    aSpecialEvents: [],
    aWeeklyEvents: []
  };

  Location timezone;

  dynamic get defaultValue => attributes[aDefaultValue];

  List<Map> storedEvents = [];
  List<Map> specialEvents = [];
  List<Map> weeklyEvents = [];

  ICalendarLocalSchedule(String path) : super(path) {
    try {
      timezone = TimezoneEnv.getLocation(getChild("timezone") == null ? TimezoneEnv.local.name : (getChild("timezone") as SimpleNode).value);
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

    link.addNode("${path}/current", {
      r"$name": "Current Value",
      r"$type": "dynamic"
    });

    link.addNode("${path}/next", {
      r"$name": "Next Value",
      r"$type": "dynamic"
    });

    TimezoneNode nd = provider.getNode("${path}/${TimezoneNode.pathName}");
    if (nd == null) {
      nd = provider.addNode("${path}/${TimezoneNode.pathName}", {
        r"$name": "Timezone",
        r"$type": "string",
        r"$is": TimezoneNode.isType,
        "?value": TimezoneEnv.local.name,
        r"$writable": "write"
      });
      nd.schedule = this;
    } else {
      nd.schedule = this;
      nd.onSetValue(nd.value);
    }

    (nd as TimezoneNode).schedule = this;

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

    if (loadQueue != null) {
      loadQueue.add(future);
    }
  }

  bool isLoadingSchedule = false;
  String generatedCalendar;

  loadSchedule([bool isUpdate = false]) async {
    await runZoned(() async {
      await _loadSchedule(isUpdate);
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
        link.val("${path}/current", v.value);
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
        link.val("${path}/current", firstCurrent.value);
      } else {
        link.val("${path}/current", defaultValue);
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

        {
          for (var key in event.rule.keys) {
            var val = event.rule[key];

            ruleString += "${key}=${val};";
          }

          if (ruleString.endsWith(";")) {
            ruleString = ruleString.substring(0, ruleString.length - 1);
          }
        }

        addOrUpdateNode(link.provider, "${rp}/edit", {
          r"$name": "Edit",
          r"$params": [
            {
              "name": "name",
              "type": "string",
              "default": event.name
            },
            {
              "name": "time",
              "type": "string",
              "editor": "daterange",
              "default": "${event.start}/${event.end}"
            },
            {
              "name": "value",
              "type": "dynamic",
              "default": event.value
            },
            {
              "name": "rule",
              "type": "string",
              "placeholder": "FREQ=DAILY",
              "default": ruleString
            }
          ],
          r"$is": "editLocalEvent",
          r"$invokable": "write"
        });
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

class HttpPortNode extends SimpleNode {
  HttpPortNode(String path) : super(path);

  @override
  onSetValue(dynamic val) {
    if (val is String) {
      try {
        val = num.parse(val);
      } catch (e) {}
    }

    if (val is num && !val.isNaN && (val > 0 || val == -1)) {
      var port = val.toInt();
      updateValue(port);
      rebindHttpServer(port);
      link.save();
      return false;
    } else {
      return false;
    }
  }
}

HttpServer server;

rebindHttpServer(int port) async {
  if (!port.isEven) {
    return;
  }

  if (server != null) {
    server.close(force: true);
    server = null;
  }
  server = await HttpServer.bind("0.0.0.0", port);
  server.listen(handleHttpRequest, onError: (e, stack) {
    logger.warning("Error in HTTP Server.", e, stack);
  }, cancelOnError: false);
}

ICalendarLocalSchedule findLocalSchedule(String name) {
  for (SimpleNode node in (link.provider as SimpleNodeProvider).nodes.values) {
    if (node is! ICalendarLocalSchedule) {
      continue;
    }

    if (name == node.displayName || node.path == "/${name}") {
      return node;
    }
  }

  return null;
}

class FetchEventsNode extends SimpleNode {
  FetchEventsNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    String timeRangeString = params["TimeRange"];
    DateTime start;
    DateTime end;

    {
      if (timeRangeString is String) {
        var parts = timeRangeString.split("/");
        start = DateTime.parse(parts[0]);
        end = DateTime.parse(parts[1]);
      }
    }
    var p = new Path(path);

    ICalendarLocalSchedule schedule = link.getNode(p.parent.path);

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
  FetchEventsForEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    String timeRangeString = params["TimeRange"];
    DateTime start;
    DateTime end;

    {
      if (timeRangeString is String) {
        var parts = timeRangeString.split("/");
        start = DateTime.parse(parts[0]);
        end = DateTime.parse(parts[1]);
      }
    }
    var p = new Path(path);

    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.parent.path);
    String thatUuid = p.parent.name;

    var results = schedule.state.getBetween(start, end).where((v) => v.eventId == thatUuid).where((x) {
      return x.time.isAfter(start) && x.time.isBefore(end);
    }).toList();

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

class AddSpecialEventNode extends SimpleNode {
  @override
  AddSpecialEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    String name = params["Name"];
    String type = params["Type"];
    String dateString = params["Date"];
    String timesString = params["Times"];

    var date = JSON.decode(dateString);
    var times = JSON.decode(timesString);

    String id = params["ReplacementId"] is! String ?
      generateToken() :
      params["ReplacementId"];

    if (id.trim().isEmpty) {
      id = generateToken();
    }

    var p = new Path(path);
    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.path);
    var fe = schedule.specialEvents.firstWhere((e) => e["id"] == id, orElse: () => null);
    var m = {
      "type": type == null ? "Date" : type,
      "date": date,
      "times": times,
      "name": name,
      "id":  id
    };

    if (fe != null) {
      schedule.specialEvents[schedule.specialEvents.indexOf(fe)] = m;
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
  FetchSpecialEventsNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async* {
    var p = new Path(path);
    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.path);
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
  RemoveSpecialEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var p = new Path(path);
    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.path);
    schedule.specialEvents.removeWhere((e) => e["id"] == params["Id"]);
    await schedule.loadSchedule(false);
  }
}

class TimezoneNode extends SimpleNode {
  static const String isType = "timezone";
  static const String pathName = "timezone";
  ICalendarLocalSchedule schedule;

  TimezoneNode(String path) : super(path);

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
          link.save();
        });
        schedule.loadSchedule(true);
        return false;
      }
    }
    return true;
  }
}
