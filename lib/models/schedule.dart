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

  void add(Event e) {
    var nextTs = e.timeRange.nextTs();

    events.add(e);

    if (nextTs == null) return; // All events took place in the past.
    // TODO: Decide if it should become active right now.
    if (e.timeRange.includes(new DateTime.now())) {
      if (current == null) {
        current = e;
        if (_timer.isActive) _timer.cancel(); // TODO: Setup timer

      }
    }

    if (_active.isEmpty) {
      _active.add(e);
    } else {
      var ind = getTsIndex(_active, nextTs);
      _active.insert(ind, e);
      next = _active.first;
    }

    // TODO: It should add events in position rather than
  }

  /// Makes the passed Event e, the current event.
  void _setCurrent(Event e) {
    var now = new DateTime.now();

    current = e;
    _controller.add(e.value);

    if (_timer != null && _timer.isActive) _timer.cancel();
    var end = now.add(e.timeRange.period);
    var nextTs = _getNextTs();
    // no more events after this currently, so start timer until the end
    // of the current period.
    if (nextTs == null || nextTs.isAfter(end)) {
      _timer = new Timer(e.timeRange.period, _timerEnd);
    } else {
      // Next timeStamp is before end of current.
      _timer = new Timer(nextTs.difference(now), _timerEnd);
    }
  }

  DateTime _getNextTs() {
    List<DateTime> times = events
        .map((Event e) => e.timeRange.nextTs())
        .toList()
        ..sort();
    if (times.isEmpty) return null;
    return times.first;
  }

  // Called when there are no other subscriptions to the stream. Add the current
  // value when a listen occurs. Won't always provide the value but better than
  // none at all
  void _onListen() {
    _controller.add(currentValue);
  }

  void _timerEnd() {
    // TODO: Timer is over. Next value or default.
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
    break; // don't keep iterating, we know where to insert
  }

  return ind;
}