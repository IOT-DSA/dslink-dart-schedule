import 'dart:async';

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
  static const String _remove = 'remove';
  static const String _events = 'events';
  static const String _schedule = r'$schedule';
  static const String _def = 'defaultValue';

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

    schedule.values.listen(_handleValue, onError: (e) {
      logger.warning('Schedule "$name" encountered an unexpected error ' +
          'listening for values.', e);
    });

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
    if (schedule.next != next) _updateNext();
  }

  /// Called by the [DefaultValueNode] in onSetValue.
  void setDefaultValue(Object value) {
    schedule.defaultValue = value;
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
    r'$name': 'Default Value',
    r'$type': 'dynamic',
    r'$writable': 'write',
    r'?value': value
  };

  final LinkProvider _link;
  DefaultValueNode(String path, this._link) : super(path) {
    serializable = false;
  }

  @override
  // Called when `@set` is called on the default value.
  bool onSetValue(Object value) {
    var schedNode = getSchedule();
    schedNode.setDefaultValue(parseInputValue(value));
    _link.save();

    return false; // False to accept value. ¯\_(ツ)_/¯
  }
}