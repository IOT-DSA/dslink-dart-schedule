import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import "package:dslink_schedule/ical.dart" as ical;
import "package:dslink_schedule/calendar.dart";

import "package:dslink_schedule/utils.dart";

import "package:http/http.dart" as http;
import "package:timezone/standalone.dart";

LinkProvider link;
http.Client httpClient = new http.Client();
SimpleNodeProvider provider;

main(List<String> args) async {
  await initializeTimeZone();

  link = new LinkProvider(args, "Schedule-", profiles: {
    "addiCalRemoteSchedule": (String path) => new AddICalRemoteScheduleNode(path),
    "addiCalLocalSchedule": (String path) => new AddICalLocalScheduleNode(path),
    "iCalRemoteSchedule": (String path) => new ICalendarRemoteSchedule(path),
    "iCalLocalSchedule": (String path) => new ICalendarLocalSchedule(path),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider as MutableNodeProvider),
    "event": (String path) => new EventNode(path),
    "addLocalEvent": (String path) => new AddLocalEventNode(path),
    "httpPort": (String path) => new HttpPortNode(path)
  }, autoInitialize: false);

  loadQueue = [];

  link.init();

  provider = link.provider;

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

  await rebindHttpServer(link.val("/httpPort"));

  link.addNode("/addiCalLocalSchedule", {
    r"$is": "addiCalLocalSchedule",
    r"$name": "Add Local Schedule",
    r"$params": [
      {
        "name": "name",
        "type": "string",
        "placeholder": "Light Schedule",
        "description": "Name of the Schedule"
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

  EventNode(String path) : super(path);

  @override
  onRemoving() {
    var p = new Path(path);
    var node = link.getNode(p.parent.parent.path);
    if (node is ICalendarLocalSchedule) {
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

class AddLocalEventNode extends SimpleNode {
  AddLocalEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params["name"];
    var timeRangeString = params["time"];
    var value = parseInputValue(params["value"]);
    var ruleString = params["rule"];

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

    if (ruleString != null) {
      rule = ical.tokenizePropertyList(ruleString);
    }

    var event = new ical.StoredEvent(name, value, range);

    if (rule != null && rule.isNotEmpty) {
      event.rule = rule;
    }

    var p = new Path(path);
    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.path);

    schedule.storedEvents.removeWhere((x) => x["name"] == name);
    schedule.storedEvents.add(event.encode());
    print(schedule.storedEvents);
    await schedule.loadSchedule();
  }
}

class AddICalLocalScheduleNode extends SimpleNode {
  AddICalLocalScheduleNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    String name = params["name"];
    dynamic defaultValue = params["defaultValue"];

    defaultValue = parseInputValue(defaultValue);

    var rawName = NodeNamer.createName(name);
    link.addNode("/${rawName}", {
      r"$is": "iCalLocalSchedule",
      r"$name": name,
      "@defaultValue": defaultValue
    });

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
      r"$name": "Value Changes In",
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
        link.removeNode("${path}/events/${x}");
      });

      // Wait so that the removing of those events can be flushed.
      await new Future.delayed(const Duration(milliseconds: 4));

      var events = ical.loadEvents(content);
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
  dynamic get defaultValue => attributes[r"@defaultValue"];
  List<Map> storedEvents = [];

  ICalendarLocalSchedule(String path) : super(path);

  Disposable changerDisposable;

  @override
  onCreated() {
    if (attributes["@events"] is List) {
      storedEvents.clear();
      for (var element in attributes["@events"]) {
        if (element is Map) {
          storedEvents.add(element);
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

    link.addNode("${path}/next_ts", {
      r"$name": "Next Value Timestamp",
      r"$type": "dynamic"
    });

    link.addNode("${path}/stc", {
      r"$name": "Value Changes In",
      r"$type": "number",
      "@unit": "seconds"
    });

    link.addNode("${path}/events", {
      r"$name": "Events",
      "addEvent": {
        r"$name": "Add Event",
        r"$is": "addLocalEvent",
        r"$params": [
          {
            "name": "name",
            "type": "string",
            "placeholder": "Turn on Light"
          },
          {
            "name": "time",
            "type": "string",
            "editor": "daterange"
          },
          {
            "name": "value",
            "type": "dynamic",
            "description": "Event Value"
          },
          {
            "name": "rule",
            "type": "string",
            "placeholder": "FREQ=DAILY"
          }
        ],
        r"$invokable": "write"
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

  loadSchedule() async {
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
          link.removeNode("${path}/events/${x}");
        }
      });

      // Wait so that the removing of those events can be flushed.
      await new Future.delayed(const Duration(milliseconds: 2));

      ical.CalendarObject object;

      {
        List<ical.StoredEvent> loadedEvents = storedEvents
            .map((x) => ical.StoredEvent.decode(x))
            .where((x) => x != null)
            .toList();

        var data = await ical.generateCalendar(displayName);
        var tokens = ical.tokenizeCalendar(data);
        object = ical.parseCalendarObjects(tokens);
        if (object.properties["VEVENT"] == null) {
          object.properties["VEVENT"] = [];
        }
        List<ical.CalendarObject> fakeEventObjects = object.properties["VEVENT"];
        for (var n in loadedEvents) {
          var e = n.toCalendarObject();
          e.parent = object;
          fakeEventObjects.add(n.toCalendarObject());
        }
      }

      StringBuffer buff = new StringBuffer();
      ical.serializeCalendar(object, buff);
      generatedCalendar = buff.toString();

      var events = ical.loadEvents(generatedCalendar);
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
  if (server != null) {
    server.close(force: true);
    server = null;
  }
  server = await HttpServer.bind("0.0.0.0", port);
  server.listen(handleHttpRequest, onError: (e, stack) {
    logger.warning("Error in HTTP Server.", e, stack);
  }, cancelOnError: false);
}

handleHttpRequest(HttpRequest request) async {
  HttpResponse response = request.response;
  String path = request.uri.path;

  end(input, {int status: HttpStatus.OK}) async {
    response.statusCode = status;

    if (input is String) {
      response.write(input);
    } else if (input is Uint8List) {
      response.headers.contentType = ContentType.BINARY;
      response.add(input);
    } else if (input is Map || input is List) {
      response.headers.contentType = ContentType.JSON;
      response.writeln(const JsonEncoder.withIndent("  ").convert(input));
    } else {
    }

    await response.close();
  }

  if (path == "/") {
    await end({
      "ok": true,
      "response": {
        "message": "DSA Schedule Server"
      }
    });
    return;
  } else if (path.startsWith("/calendars/") && path.endsWith(".ics")) {
    var name = path.substring(11, path.length - 4);

    for (var node in provider.nodes.values) {
      if (node is! ICalendarLocalSchedule) {
        continue;
      }

      if (name == node.displayName) {
        ICalendarLocalSchedule sched = node;
        if (sched.generatedCalendar != null) {
          await end(sched.generatedCalendar);
          return;
        }
      }
    }
  }

  await end({
    "ok": false,
    "error": {
      "message": "${path} was not found.",
      "code": "http.not.found"
    }
  }, status: HttpStatus.NOT_FOUND);
}
