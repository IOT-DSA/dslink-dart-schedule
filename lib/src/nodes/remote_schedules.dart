import 'dart:async';

import 'package:dslink/dslink.dart';
import 'package:dslink/nodes.dart' show NodeNamer;
import 'package:dslink/utils.dart';
import "package:http/http.dart" as http;
import 'package:timezone/timezone.dart' as TimezoneEnv;

import "package:dslink_schedule/calendar.dart";
import 'package:dslink_schedule/utils.dart';
import "package:dslink_schedule/ical.dart" as ical;

import 'event.dart';

class AddICalRemoteScheduleNode extends SimpleNode {
  static const String pathName = "addiCalRemoteSchedule";
  static const String isType = "addiCalRemoteSchedule";

  //Params
  static const String _name = "name";
  static const String _url = "url";
  static const String _defaultValue = "defaultValue";

  static Map<String, dynamic> def() => {
    r"$is": isType,
    r"$name": "Add Remote Schedule",
    r"$params": [
      {
        "name": _name,
        "type": "string",
        "placeholder": "Light Schedule",
        "description": "Name of the Schedule"
      },
      {
        "name": _url,
        "type": "string",
        "placeholder": "http://my.calendar.host/calendar.ics",
        "description": "URL to the iCalendar File"
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
  AddICalRemoteScheduleNode(String path, this._link) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    String name = params[_name];
    String url = params[_url];
    dynamic val = params[_defaultValue];

    val = parseInputValue(val);

    var rawName = NodeNamer.createName(name);
    provider.addNode("/$rawName", ICalendarRemoteSchedule.def(url, val));

    _link.save();
  }
}

class ICalendarRemoteSchedule extends SimpleNode {
  static const String isType = "iCalRemoteSchedule";
  // Attributes
  static const String _defaultValue = '@defaultValue';
  static const String _url = '@url';
  static const String _calendar = '@calendar';
  // Value Nodes
  static const String _current = 'current';
  static const String _next = 'next';
  static const String _next_ts = 'next_ts';
  static const String _stc = 'stc';
  static const String _events = 'events';

  static const String _remove = 'remove';

  dynamic get defaultValue => attributes[_defaultValue];
  String get url => attributes[_url];
  String get backupCalendar => attributes[_calendar];

  static Map<String, dynamic> def(String url, dynamic val) => {
    r"$is": isType,
    "@url": url,
    "@defaultValue": val,
    _current: {
      r'$name': 'Current Value',
      r'$type': 'dynamic'
    },
    _next: {
      r'$name': 'Next Value',
      r'$type': 'dynamic'
    },
    _next_ts: {
      r'$name': 'Next Value Timestamp',
      r'$type': 'dynamic'
    },
    _stc: {
      r'$name': 'Next Value Timer',
      r'$type': 'number',
      r'@unit': 'seconds'
    },
    _events: {
      r'$name': 'Events'
    },
    _remove: {
      r'$is': _remove,
      r'$name': 'Remove',
      r'$invokable': 'write'
    }
  };

  final List<Future> loadQueue;
  ICalendarRemoteSchedule(String path, this.loadQueue) : super(path);

  Disposable changerDisposable;

  @override
  onCreated() {
    var future = loadSchedule();

    if (loadQueue != null) {
      loadQueue.add(future);
    }
  }

  String _lastContent;

  loadSchedule([String content]) async {
    http.Client httpClient = new http.Client();
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

      provider.removeNode("${path}/error");
      provider.getNode("$path/$_events").children.keys.toList().forEach((x) {
        var n = provider.getNode("$path/$_events/$x");
        if (n is EventNode) {
          n.flagged = true;
        }
        provider.removeNode("$path/$_events/$x");
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
        provider.updateValue("$path/$_current", v.value);
        next = state.getNext();
        if (next != null) {
          provider.updateValue("$path/$_next", next.value);
          provider.updateValue("$path/$_next_ts", next.time.toIso8601String());
          nextTimestamp = next.time;
        } else {
          provider.updateValue("$path/$_next", defaultValue);
          provider.updateValue("$path/$_next_ts", v.endsAt.toIso8601String());
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
          provider.updateValue("$path/$_stc", duration.inSeconds);
        }
      });

      var eventList = icalProvider.listEvents();

      var i = 0;
      for (var event in eventList) {
        i++;

        var map = event.asNode(i);

        SimpleNode eventNode = provider.addNode("$path/$_events/$i", map);
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
      provider.addNode("${path}/error", {
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
