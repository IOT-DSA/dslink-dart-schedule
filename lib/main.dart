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

import "package:xml/xml.dart" as XML;

import 'nodes/nodes.dart';
import 'nodes/common.dart';

import 'src/loading_queue.dart';

part "src/http.dart";

LinkProvider link;
http.Client httpClient = new http.Client();

main(List<String> args) async {
  String basePath = Directory.current.path;

  var loadQueue = new LoadingQueue();

  link = new LinkProvider(args, "Schedule-", profiles: {
    "addiCalRemoteSchedule": (String path) => new AddICalRemoteScheduleNode(path),
    AddICalLocalScheduleNode.isType: (String path) => new AddICalLocalScheduleNode(path, link),
    "iCalRemoteSchedule": (String path) => new ICalendarRemoteSchedule(path, loadQueue),
    ICalendarLocalScheduleImpl.isType: (String path) => new ICalendarLocalScheduleImpl(path, link, loadQueue),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider as MutableNodeProvider, onDelete: () {
      link.save();
    }),
    EventNode.isType: (String path) => new EventNode(path),
    AddLocalEventNode.isType: (String path) => new AddLocalEventNode(path),
    "httpPort": (String path) => new HttpPortNode(path),
    EditLocalEventNode.isType: (String path) => new EditLocalEventNode(path),
    "fetchEvents": (String path) => new FetchEventsNode(path),
    "fetchEventsForEvent": (String path) => new FetchEventsForEventNode(path),
    "addLocalSpecialEvent": (String path) => new AddSpecialEventNode(path),
    "fetchSpecialEvents": (String path) => new FetchSpecialEventsNode(path),
    "removeSpecialEvent": (String path) => new RemoveSpecialEventNode(path),
    TimezoneNode.isType: (String path) => new TimezoneNode(path, link)
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

  await Future.wait(loadQueue.queue);
  loadQueue.clear();

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

class ICalendarRemoteSchedule extends SimpleNode {
  dynamic get defaultValue => attributes[r"@defaultValue"];
  String get url => attributes["@url"];
  String get backupCalendar => attributes["@calendar"];

  final LoadingQueue loadQueue;
  ICalendarRemoteSchedule(String path, this.loadQueue) : super(path);

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

    loadQueue.add(future);
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
