import "dart:async";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import "package:dslink_schedule/ical.dart" as ical;
import "package:dslink_schedule/calendar.dart";

import "package:dslink_schedule/utils.dart";

import "package:http/http.dart" as http;

LinkProvider link;
http.Client httpClient = new http.Client();

main(List<String> args) async {
  link = new LinkProvider(args, "Schedule-", profiles: {
    "addiCalRemoteSchedule": (String path) => new AddICalRemoteScheduleNode(path),
    "iCalRemoteSchedule": (String path) => new ICalendarRemoteSchedule(path),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider as MutableNodeProvider)
  }, autoInitialize: false);

  loadQueue = [];

  link.init();

  link.addNode("/addiCalRemoteSchedule", {
    r"$is": "addiCalRemoteSchedule",
    r"$name": "Add iCalendar Remote Schedule",
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

        var map = {
          r"$name": event.name,
          "id": {
            r"$name": "ID",
            r"$type": "number",
            "?value": i
          },
          "value": {
            r"$name": "Value",
            r"$type": "dynamic",
            "?value": event.value
          }
        };

        if (event.duration != null) {
          map["duration"] = {
            r"$name": "Duration",
            r"$type": "number",
            "?value": event.duration.inSeconds,
            "@unit": "seconds"
          };
        }

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
