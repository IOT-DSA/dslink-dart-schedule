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

import "package:path/path.dart" as pathlib;

import "package:xml/xml.dart" as XML;
import "package:crypto/crypto.dart";

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
  }, autoInitialize: false, encodePrettyJson: true);

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

  var portValue = link.val("/httpPort");
  await rebindHttpServer(portValue is String ? int.parse(portValue) : portValue);

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

  bool sendToHandler = true;

  @override
  onRemoving() {
    var p = new Path(path);
    var node = link.getNode(p.parent.parent.path);
    if (node is ICalendarLocalSchedule && sendToHandler) {
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
          EventNode en = link.getNode("${path}/events/${x}");
          en.sendToHandler = false;
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
        rootCalendarObject = object;
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
      "@defaultValue": attributes["@defaultValue"]
    };

    if (attributes["@calendar"] != null) {
      map["@calendar"] = attributes["@calendar"];
    }

    map["@events"] = storedEvents;

    return map;
  }

  ical.CalendarObject rootCalendarObject;
  ValueCalendarState state;
  ical.ICalendarProvider icalProvider;
  Timer untilTimer;
  Disposable httpTimer;

  String calculateTag() {
    var sha = new SHA256();
    var json = const JsonEncoder().convert(storedEvents);
    sha.add(const Utf8Encoder().convert(json));
    return CryptoUtils.bytesToHex(sha.close());
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

handleHttpRequest(HttpRequest request) async {
  logger.fine("[Schedule HTTP] ${request.method} ${request.uri}");
  request.headers.forEach((a, b) {
    logger.fine("[Schedule HTTP] ${a}: ${request.headers.value(a)}");
  });

  HttpResponse response = request.response;
  String path = request.uri.path;
  String method = request.method;

  end(input, {int status: HttpStatus.OK}) async {
    logger.fine("[Schedule HTTP] Reply with status code ${status}:\n${input}");
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

  sendNotFound() async {
    await end({
      "ok": false,
      "error": {
        "message": "${path} was not found.",
        "code": "http.not.found"
      }
    }, status: HttpStatus.NOT_FOUND);
  }

  var parts = pathlib.url.split(path);

  if (path.startsWith("/calendars/")) {
    response.headers.set("DAV", "1, 2, calendar-access");
    response.headers.set("Allow", "OPTIONS, PROPFIND, HEAD, GET, REPORT, PROPPATCH, PUT, DELETE, POST");
  }

  if (path == "/") {
    await end({
      "ok": true,
      "response": {
        "message": "DSA Schedule Server"
      }
    });
    return;
  } else if (method == "GET" &&
      parts.length == 3 &&
      parts[1] == "calendars" &&
      pathlib.extension(path) == ".ics") {
    var name = pathlib.basenameWithoutExtension(parts[2]);
    var node = findLocalSchedule(name);
    if (node != null && node.generatedCalendar != null) {
      await end(node.generatedCalendar);
      return;
    }
  } else if (parts.length == 5 &&
      parts[1] == "calendars" &&
      parts[3] == "events" &&
      parts[4].endsWith(".ics")) {
    var node = findLocalSchedule(parts[2]);
    var name = pathlib.basenameWithoutExtension(parts[4]);
    if (node != null && node.generatedCalendar != null) {
      if (method == "GET") {
        List<Map> events = node.storedEvents;
        for (var x in events) {
          if (x["id"] == name || x["name"] == name) {
            var allEvents = node.rootCalendarObject.properties["VEVENT"];
            ical.CalendarObject event;

            for (ical.CalendarObject t in allEvents) {
              if (t.properties["UID"] == x["id"]) {
                event = t;
              }
            }

            var cal = new ical.CalendarObject();
            cal.type = "VCALENDAR";
            cal.properties.addAll({
              "PRODID": "PRODID:-//Distributed Services Architecture//Schedule DSLink//EN",
              "VERSION": "2.0",
              "CALSCALE": "GREGORIAN",
              "METHOD": "PUBLISH"
            });
            cal.properties["VEVENT"] = [event];
            var buff = new StringBuffer();
            ical.serializeCalendar(cal, buff);
            await end(buff.toString());
            return;
          }
        }
      }
    }

    if (method == "PUT") {
      String input = await request
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .join("\n");

      if (input.isEmpty) {
        await end("Ok.");
        return;
      }

      var tokens = ical.tokenizeCalendar(input);
      ical.CalendarObject obj = ical.parseCalendarObjects(tokens);
      List events = obj.properties["VEVENT"];
      if (events is! List || events.isEmpty) {
        await end({
          "ok": false,
          "error": {
            "message": "Invalid Input.",
            "code": "http.calendar.invalid"
          }
        }, status: HttpStatus.NOT_ACCEPTABLE);
        return;
      }

      List<Map> out = [];

      for (ical.CalendarObject x in events) {
        DateTime startTime = x.properties["DTSTART"];
        DateTime endTime = x.properties["DTEND"];
        String id = x.properties["UID"];
        var buff = new StringBuffer();
        ical.serializeCalendar(x.properties["RRULE"], buff);
        String rule = buff.toString();

        if (id == null) {
          id = generateToken();
        }

        var map = {
          "name": x.properties["SUMMARY"],
          "id": id
        };

        if (startTime != null) {
          map["start"] = startTime.toIso8601String();
        }

        if (endTime != null) {
          map["end"] = endTime.toIso8601String();
        }

        if (rule != null && rule != "null\n" && rule != "null") {
          map["rule"] = rule;
        }

        if (x.properties["DESCRIPTION"] != null) {
          var desc = x.properties["DESCRIPTION"];
          if (desc is Map && desc.keys.length == 1 && desc.keys.single == "value") {
            desc = parseInputValue(desc["value"]);
          }
          map["value"] = parseInputValue(desc);
        }

        out.add(map);
      }

      ml: for (var e in node.storedEvents.toList()) {
        for (var l in out) {
          if (e["id"] == l["id"]) {
            node.storedEvents.remove(e);
            continue ml;
          }
        }
      }

      node.storedEvents.addAll(out);
      await node.loadSchedule();
      await end({}, status: HttpStatus.CREATED);
      return;
    }
  } else if (path.startsWith("/calendars/") && parts.length >= 2 && (method == "PROPFIND" || method == "OPTIONS")) {
    String name;
    if (parts.length >= 3) {
      name = parts[2];
    } else {
      name = "";
    }

    if (name.endsWith(".ics")) {
      name = name.substring(0, name.length - 4);
    }

    ICalendarLocalSchedule schedule = findLocalSchedule(name);

    if (name.isNotEmpty && schedule == null) {
      await sendNotFound();
      return;
    }

    response.headers.set("ETag", schedule.calculateTag());

    var input = await request
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .join("\n");

    if (input.isEmpty) {
      await end("Ok.");
      return;
    }

    logger.fine("[Schedule HTTP] Sent ${request.method} to ${path}:\n${input}");

    XML.XmlDocument doc = XML.parse(input);
    XML.XmlElement prop = doc.rootElement
        .findElements("prop", namespace: "DAV:")
        .first;

    var results = <XML.XmlName, dynamic>{};
    var out = new XML.XmlBuilder();
    var notOut = [];

    Uri syncTokenUri = request.requestedUri;
    syncTokenUri = syncTokenUri
        .replace(path: pathlib.join(syncTokenUri.path, "sync", "500"));
    for (XML.XmlElement e in prop.children.where((x) => x is XML.XmlElement)) {
      var name = e.name.local;

      if (name == "displayname") {
        results[e.name] = schedule.displayName;
      } else if (name == "getctag" || name == "getetag") {
        results[e.name] = schedule.calculateTag();
      } else if (name == "principal-URL") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/");
        };
      } else if (name == "getcontenttype") {
        results[e.name] = (XML.XmlBuilder out) {
          out.text("text/calendar; component=vevent");
        };
      } else if (name == "calendar-home-set" && !path.startsWith(".ics")) {
        results[e.name] = (XML.XmlBuilder out) {
          if (!path.endsWith(".ics")) {
            out.element("href", namespace: "DAV:", nest: "/" + parts.skip(1).take(2).join("/") + ".ics");
          }
        };
      } else if (name == "current-user-principal") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/" + parts.skip(1).take(2).join("/") + ".ics");
        };
      } else if (name == "calendar-user-address-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/" + parts.skip(1).take(2).join("/") + ".ics");
        };
      } else if (name == "supported-report-set") {
        results[e.name] = (XML.XmlBuilder out) {
          for (var name in const ["calendar-multiget"]) {
            out.element("supported-report", namespace: "DAV:", nest: () {
              out.element("report", namespace: "DAV:", nest: name);
            });
          }
        };
      } else if (name == "calendar-collection-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", nest: schedule.displayName);
        };
      } else if (name == "principal-collection-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/" + parts.skip(1).take(2).join("/") + ".ics");
        };
      } else if (name == "supported-calendar-component-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("comp", namespace: "DAV:", attributes: {
            "name": "VEVENT"
          });
        };
      } else if (name == "sync-token") {
        results[e.name] = (XML.XmlBuilder out) {
          out.text(syncTokenUri.toString());
        };
      } else if (name == "resourcetype") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("collection");
          out.element("calendar");
          out.element("principal");
        };
      } else if (name == "sync-level") {
        results[e.name] = "1";
      } else if (name == "owner" || name == "source") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: path);
        };
      } else if (name == "calendar-description") {
        results[e.name] = schedule.displayName;
      } else if (name == "calendar-color") {
        results[e.name] = "FF5800";
      } else {
        notOut.add(e.name);
      }
    }

    response.headers.contentType =
        ContentType.parse("application/xml; charset=utf-8");

    out.processing("xml", 'version="1.0" encoding="utf-8"');

    out.element("multistatus", namespace: "DAV:", namespaces: {
      "DAV:": "",
      "http://calendarserver.org/ns/": "CS"
    }, nest: () {
      out.element("href", namespace: "DAV:",
          nest: path);
      out.element("sync-token", namespace: "DAV:",
          nest: "/" + parts.skip(1).take(2).join("/") + ".ics");
      out.element("response", namespace: "DAV:", nest: () {
        out.element("href", namespace: "DAV:", nest: path);
        out.element("propstat", namespace: "DAV:", nest: () {
          out.element("prop", namespace: "DAV:", nest: () {
            for (XML.XmlName key in results.keys) {
              out.element(key.local, namespace: "DAV:", nest: () {
                if (results[key] is String || results[key] is num) {
                  out.text(results[key]);
                } else if (results[key] is Function) {
                  results[key](out);
                }
              });
            }
          });


          out.element("status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
        });

        out.element("propstat", namespace: "DAV:", nest: () {
          out.element("prop", namespace: "DAV:", nest: () {
            for (XML.XmlName key in notOut) {
              if (key.prefix != null) {
                if (key.namespaceUri != "DAV:" && key.namespaceUri != "http://calendarserver.org/ns/") {
                  try {
                    out.namespace(key.namespaceUri, key.prefix);
                  } catch (e) {}
                }

                out.element(key.local, namespace: key.namespaceUri);
              } else {
                out.element(key.local);
              }
            }
          });

          out.element(
              "status", namespace: "DAV:", nest: "HTTP/1.1 404 Not Found");
        });
      });

      if (request.headers.value("depth") != "0") {
        out.element("response", namespace: "DAV:", nest: () {
          out.element("propstat", namespace: "DAV:", nest: () {
//            out.element("prop", namespace: "DAV:", nest: () {
//              for (XML.XmlName key in results.keys) {
//                if (!(const ["resourcetype", "getcontentype", "getetag"].contains(key.local))) {
//                  continue;
//                }
//
//                out.element(key.local, namespace: "DAV:", nest: () {
//                  if (key.local != "resourcetype") {
//                    if (results[key] is String || results[key] is num) {
//                      out.text(results[key]);
//                    } else if (results[key] is Function) {
//                      results[key](out);
//                    }
//                  }
//                });
//              }
//            });

            for (XML.XmlName key in results.keys) {
              if (!(const ["resourcetype", "getcontentype", "getetag"].contains(key.local))) {
                continue;
              }

              out.element(key.local, namespace: "DAV:", nest: () {
                if (key.local != "resourcetype") {
                  if (results[key] is String || results[key] is num) {
                    out.text(results[key]);
                  } else if (results[key] is Function) {
                    results[key](out);
                  }
                }
              });
            }

            out.element(
                "status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
          });
        });
      }
    });

    await end(out.build().toXmlString(pretty: true), status: 207);
    return;
  }

  await sendNotFound();
}

ICalendarLocalSchedule findLocalSchedule(String name) {
  for (SimpleNode node in provider.nodes.values) {
    if (node is! ICalendarLocalSchedule) {
      continue;
    }

    if (name == node.displayName || node.path == "/${name}") {
      return node;
    }
  }

  return null;
}
