import 'dart:async';

import 'event.dart';

/// A schedule contains a default value (may be null) and a list of 0 or more
/// events that occur during that schedule.
class Schedule {
  /// Internal reference name for the schedule.
  String name;
  /// The schedule will provide this Event when no event is active.
  Object defaultValue;
  /// List of events that make up the schedule.
  List<Event> events;
  /// The event that is currently active.
  Event current;
  /// Next event scheduled to be active.
  Event next;
  /// Stream of values from the schedule which are generated at the appropriate
  /// time.
  Stream<Object> get values => _controller.stream;

  Object get currentValue => current != null ? current.value : defaultValue;

  // These are used for to/from json encoding
  static const String _name = 'name';
  static const String _value = 'value';
  static const String _events = 'events';

  Timer _timer;
  StreamController<Object> _controller;
  List<Event> _active;
  bool _isEnd; // When timer ends revert to default rather than start new

  /// Create a new schedule with the specified name, and specified defaultValue.
  Schedule(this.name, this.defaultValue) {
    events = new List<Event>();
    _active = new List<Event>();
    _controller = new StreamController.broadcast(onListen: _onListen);
  }

  /// Create a new Schedule from a json map of a previously exported scheduled.
  Schedule.fromJson(Map<String, dynamic> map) {
    name = map[_name];
    defaultValue = map[_value];
    var eList = map[_events] as List<Map>;

    events = new List<Event>(eList.length);
    for (var e in eList) {
      events.add(new Event.fromJson(e));
    }

    // TODO Figure out how to handle getting the next event in the schedule.
  }

  /// Add an event to this schedule.
  void add(Event e) {
    var nextTs = e.timeRange.nextTs();

    var ind = getTsIndex(events, nextTs);
    events.insert(ind, e);

    // Check if it should become active right now.
    if (e.timeRange.includes(new DateTime.now())) {
      _setCurrent(getPriority(current, e));
    }

    // Not current, and all events took place in the past.
    if (nextTs == null) return;

    if (_active.isEmpty) {
      _active.add(e);
    } else {
      ind = getTsIndex(_active, nextTs);
      _active.insert(ind, e);
      next = _active.first;
    }
  }

  /// Makes the passed Event e, the current event, it will also try to calculate
  /// the next event and queue it up.
  void _setCurrent(Event e) {
    // If it's already current, no need to change anything.
    if (current == e) return;

    var now = new DateTime.now();
    current = e;
    // If null then send the defaultValue
    if (e == null) {
      _controller.add(defaultValue);
    } else {
      _controller.add(e.value);
    }

    if (_timer != null && _timer.isActive) _timer.cancel();

    var nextTs = _getNextTs();
    if (e == null && nextTs != null) {
      // No current Event, create timer until next event.
      _timer = new Timer(nextTs.difference(now), _timerEnd);
      _isEnd = false;
      return;
    }

    var end = now.add(e.timeRange.period);
    // no more events after this currently, so start timer until the end
    // of the current period.
    if (nextTs == null || nextTs.isAfter(end)) {
      _timer = new Timer(e.timeRange.period, _timerEnd);
      _isEnd = true;
    } else {
      // Next timeStamp is before end of current.
      _timer = new Timer(nextTs.difference(now), _timerEnd);
      _isEnd = false;
    }
  }

  // Returns the DateTime stamp of the next event. This also has a side effect
  // that will assign the next Event to the `next` value of the Schedule
  DateTime _getNextTs() {
    if (_active.isEmpty) return next = null;

    _active.sort((Event a, Event b) {
      var tsA = a.timeRange.nextTs();
      return tsA.compareTo(b.timeRange.nextTs());
    });

    next = _active.first;
    return next.timeRange.nextTs();
  }

  // Called when there are no other subscriptions to the stream. Add the current
  // value when a listen occurs. Won't always provide the value but better than
  // none at all
  void _onListen() {
    _controller.add(currentValue);
  }

  // Called when the _timer ends. It call setCurrent with null or the appropriate
  // event.
  void _timerEnd() {
    // Should be returning to default.
    if (_isEnd) {
      // Check and see if the event should be removed from active.
      var next = current.timeRange.nextTs();
      if (next == null) {
        _active.removeWhere((Event e) => e.id == current.id);
      }

      _setCurrent(null);
      return;
    }

    if (next == null) {
      var nextTs = _getNextTs();
      if (nextTs == null) return;
    }

    _setCurrent(next);
  }

  // Should schedules provide the values with a stream? Stream of values
  // Broadcast stream, since that won't block when not listened.
}

/// Get the index into which an event at the specified DateTime dt should be
/// inserted into the list.
int getTsIndex(List<Event> list, DateTime dt) {
  var ind = list.length;
  var now = new DateTime.now();
  for (int i = 0; i < list.length; i++) {
    var eTs = list[i].timeRange.nextTs(now);
    if (eTs == null || eTs.isBefore(dt)) continue;

    ind = i;
    break;
  }

  return ind;
}
