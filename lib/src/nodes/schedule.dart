import 'dart:async';
import 'dart:convert' show JSON;

import 'package:dslink/dslink.dart';
import 'package:dslink/nodes.dart' show NodeNamer;
import 'package:dslink/utils.dart' show logger;

import 'package:dslink_schedule/utils.dart';
import 'package:dslink_schedule/schedule.dart';

import 'events.dart';
import 'common.dart';

class AddSchedule extends SimpleNode {
  static const String pathName = 'addSchedule';
  static const String isType = 'addScheduleNode';

  static const String _name = 'name';
  static const String _defVal = 'defaultValue';

  static Map<String, dynamic> def() => {
    r'$is': isType,
    r'$name': 'Add Schedule',
    r'$params': [
      {
        'name': _name,
        'type': 'string',
        'placeholder': 'Light Schedule',
        'description': 'Name of the schedule'
      },
      {
        'name': _defVal,
        'type': 'dynamic',
        'description': 'Default value for the schedule',
        'default': 0
      }
    ],
    r'$invokable': 'write'
  };

  final LinkProvider _link;
  AddSchedule(String path, this._link) : super(path);

  @override
  void onInvoke(Map<String, dynamic> params) {
    var name = params[_name];
    Object defVal = parseInputValue(params[_defVal]);

    var encodeName = NodeNamer.createName(name);
    var schedNode = provider.getNode('/$encodeName');
    if (schedNode != null) {
      throw new ArgumentError.value(name,
          'name',
          'A schedule by that name already exists');
    }

    var sched = new Schedule(name, defVal);
    provider.addNode('/$encodeName', ScheduleNode.def(sched));
    _link.save();
  }
}

class ScheduleNode extends SimpleNode {
  static const String isType = 'scheduleNode';

  static const String _current = 'current';
  static const String _next = 'next';
  static const String _next_ts = 'next_ts';
  static const String _stc = 'stc';
  static const String _events = 'events';
  static const String _schedule = r'$schedule';

  static Map<String, dynamic> def(Schedule sched) => {
      r'$name': sched.name,
      r'$is': isType,
      _schedule: sched.toJson(),
      _current: {r'$name': 'Current Value', r'$type': 'dynamic'},
      _next: {r'$name': 'Next Value', r'$type': 'dynamic'},
      _next_ts: {r"$name": "Next Value Timestamp", r"$type": 'string'},
      _stc: {
        r"$name": "Next Value Timer",
        r"$type": "number",
        "@unit": "seconds"
      },
      ExportSchedule.pathName: ExportSchedule.def(),
      RemoveAction.pathName: RemoveAction.def(),
      _events: {
        r"$name": "Events",
        AddSingleEvent.pathName: AddSingleEvent.def(),
        AddMomentEvent.pathName: AddMomentEvent.def(),
        AddRecurringEvents.pathName: AddRecurringEvents.def()
      }
  };

  Schedule schedule;

  // Timer used to count each second (for next value duration in seconds node)
  Timer _secTimer;
  final LinkProvider _link;
  ScheduleNode(String path, this._link) : super(path);

  @override
  void onCreated() {
    var sch = getConfig(_schedule);
    if (sch == null) {
      logger.warning('Schedule $name encoding is unexpectedly null.');
      remove();
    }

    schedule = new Schedule.fromJson(sch);
    for (var e in schedule.events) {
      var en = provider.addNode('$path/$_events/${e.id}', EventsNode.def(e)) as EventsNode;
      en.event = e;
    }

    provider.addNode('$path/${DefaultValueNode.pathName}',
        DefaultValueNode.def(schedule.defaultValue));

    _addMissing(ExportSchedule.pathName, ExportSchedule.def());

    schedule.values.listen(_handleValue, onError: (e) {
      logger.warning('Schedule "$name" encountered an unexpected error ' +
          'listening for values.', e);
    });
  }

  void _addMissing(String p, Map<String, dynamic> m) {
    var nd = provider.getNode('$path/$p');
    if (nd == null) {
      provider.addNode('$path/$p', m);
    }
  }

  @override
  void onRemoving() {
    if (_secTimer != null && _secTimer.isActive) _secTimer.cancel();
    schedule.delete();
  }

  /// Called by [AddEventsNode] when an event is ready to be added to the schedule
  void addEvent(Event e) {
    schedule.add(e);
    _updateNext();
  }

  /// Called by [EventsNode] from its onRemoving callback.
  void removeEvent(String eventId) {
    var next = schedule.next;
    schedule.remove(eventId);
    // if the next scheduled event has changed, be sure to update the
    // appropriate values.
    if (schedule.next != next) _updateNext();
  }

  /// Called when an event needs to be removed and re-added back into the schedule
  /// This should help to improve efficiency somewhat.
  void replaceEvent(Event event) {
    var next = schedule.next;
    schedule.replaceEvent(event);
    if (schedule.next != next) _updateNext();
  }

  /// Called by the [DefaultValueNode] in onSetValue.
  void setDefaultValue(Object value) {
    schedule.defaultValue = value;
    _link.save();
  }

  /// Called when [EventValue] is modified
  void updateEventVal(String id, Object value) {
    // This is required in the event that event value being updated is the
    // current event.
    schedule.updateEventValue(id, value);
    if (schedule.next?.id == id) _updateNext();
  }

  /// Called by [ImportSchedule] when the schedule name already exists.
  void updateSchedule(Schedule sched, bool overwrite) {
    if (sched.defaultValue != schedule.defaultValue && overwrite) {
      setDefaultValue(sched.defaultValue);
    }

    for (var e in sched.events) {
      var ind = _indexOfEvent(e);
      // Safe to add
      if (ind == -1) {
        schedule.add(e);
        _addEventNode(e);
      } else if (overwrite) {
        // Has an existing index. Replace if overwrite.
        schedule.replaceEvent(e, ind);
        _addEventNode(e);
      }
    }
  }

  int _indexOfEvent(Event e) {
    for (var i = 0; i < schedule.events.length; i++) {
      if (schedule.events[i].id == e.id) return i;
    }

    return -1;
  }

  void _addEventNode(Event e) {
    var p = '$path/$_events/${e.id}';
    var en = provider.getNode(p) as EventsNode;
    if (en == null) {
      var en = provider.addNode(
          '$path/$_events/${e.id}', EventsNode.def(e)) as EventsNode;
      en.event = e;
    } else {
      en.updateEvent(e);
    }
  }

  @override
  Map save() {
    var m = super.save();
    if (schedule != null) m[_schedule] = schedule.toJson();

    return m;
  }

  // Update the "Next value", "Next Timestamp" and countdown timer.
  void _updateNext() {
    var nextTs = schedule.getNextTs();
    var nextNd = children[_next] as SimpleNode;
    nextNd?.updateValue(schedule.next?.value);
    var nextTsNd = children[_next_ts] as SimpleNode;
    nextTsNd?.updateValue(nextTs?.toIso8601String());

    if (schedule.next == null) {
      if (_secTimer != null && _secTimer.isActive) _secTimer.cancel();
      return;
    }

    if (_secTimer == null || !_secTimer.isActive) {
      _secTimer = new Timer.periodic(const Duration(seconds:  1), _onSecondTick);
    }
  }

  /// Callback for the Schedule.values listener. Updates current node value,
  /// next node value and helps manage Timer for next duration
  void _handleValue(Object value) {
    var curNd = children[_current] as SimpleNode;
    if (curNd == null) {
      logger.warning('Schedule $name - current value node unexpectedly null');
      return;
    }

    curNd.updateValue(value);
    _updateNext();
  }

  /// [_secTimer] Should fire once every second, when it does, it calls this
  /// method. This updates the stc node with the duration to the next event
  /// in seconds.
  void _onSecondTick(Timer t) {
    var stcNode = children[_stc] as SimpleNode;
    if (stcNode == null) return;

    var nextEvent = schedule.next;
    if (nextEvent == null) {
      t.cancel();
      stcNode.updateValue(0);
      return;
    }

    var now = new DateTime.now();
    var nextTs = nextEvent.timeRange.nextTs();

    // Rare but possible we'll have a next event but no timestamp
    if (nextTs == null) {
      nextTs = schedule.getNextTs();
      if (nextTs == null) {
        t.cancel();
        stcNode.updateValue(0);
        return;
      }
    }

    var dur = nextTs.difference(now);
    stcNode.updateValue(dur.inSeconds);
  }
}

class DefaultValueNode extends ScheduleChild {
  static const String pathName = 'defaultValue';
  static const String isType = 'defaultValueNode';

  static Map<String, dynamic> def(Object value) => {
    r'$is': isType,
    r'$name': 'Default Value',
    r'$type': 'dynamic',
    r'$writable': 'write',
    r'?value': value
  };

  DefaultValueNode(String path) : super(path) {
    serializable = false;
  }

  @override
  // Called when `@set` is called on the default value.
  bool onSetValue(Object value) {
    var schedNode = getSchedule();
    schedNode.setDefaultValue(parseInputValue(value));

    return false; // False to accept value. ¯\_(ツ)_/¯
  }
}

class ExportSchedule extends ScheduleChild {
  static const String isType = 'schedule/export';
  static const String pathName = 'export';

  static const String _json = 'json';

  static Map<String, dynamic> def() => {
    r'$is': isType,
    r'$name': 'Export Schedule',
    r'$invokable': 'write',
    r'$columns': [
      {'name': _json, 'type': 'string'}
    ]
  };
  
  ExportSchedule(String path) : super(path);
  
  @override
  Map<String, String> onInvoke(Map<String, dynamic> params) {
    var sched = getSchedule().schedule;
    var encoded = JSON.encode(sched.toJson());
    var ret = {_json: encoded};

    return ret;
  }
}

class ImportSchedule extends SimpleNode {
  static const String isType = 'schedule/import';
  static const String pathName = 'import';

  static const String _name = 'name';
  static const String _json = 'json';
  static const String _overwrite = 'overwrite';

  static Map<String, dynamic> def() => {
    r'$is': isType,
    r'$name': 'Import Schedule',
    r'$invokable': 'write',
    r'$params': [
      {
        'name': _name, 'type': 'string', 'placeholder': 'Rename schedule',
        'description': 'New name to provide schedule. Leave blank to continue' +
                        ' using existing name.'
      },
      {
        'name': _json, 'type': 'string', 'placeholder': 'Schedule JSON Object',
        'description': 'JSON serialized string of the schedule to import.'
      },
      {
        'name': _overwrite, 'type': 'bool', 'default': 'false',
        'description': 'Overwrite any conflicting events. If false, event' +
                        'conflicts will be dropped.'
      }
    ]
  };

  final LinkProvider _link;
  ImportSchedule(String path, this._link) : super(path);

  @override
  void onInvoke(Map<String, dynamic> params) {
    var json = params[_json] as String;
    if (json == null || json.isEmpty) {
      throw new ArgumentError.notNull(_json);
    }

    var nm = (params[_name] as String)?.trim();

    Map<String, dynamic> jsonMap;

    // Allow to throw error
    jsonMap = JSON.decode(json);
    var sched = new Schedule.fromJson(jsonMap);
    if (nm != null && nm.isNotEmpty) {
      sched.name = nm;
    }

    var encName = NodeNamer.createName(sched.name);
    var schedNode = provider.getNode('/$encName') as ScheduleNode;
    if (schedNode != null) {
      var overwrite = params[_overwrite] ?? false;
      schedNode.updateSchedule(sched, overwrite);
    } else {
      provider.addNode('/$encName', ScheduleNode.def(sched));
    }

    // Remove schedule once imported so it's not still floating around with
    // timers running
    sched.delete();
    _link.save();
  }
}