import 'dart:async';

import 'event.dart';
import 'timerange.dart';

// TODO: Make sure that special events block the entire day!

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
  bool _isEnd = false; // When timer ends revert to default rather than start new
  DateTime _curDay;

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
    bool isSet = false;
    var nextTs = e.timeRange.nextTs();

    var ind = getTsIndex(events, nextTs);
    events.insert(ind, e);

    // Check if it should become active right now.
    if (e.timeRange.includes(new DateTime.now())) {
      _setCurrent(getPriority(current, e));
      isSet = true; // Prevent redundant setting timer.
    }

    // Not current, and all events took place in the past.
    if (nextTs == null) return;
    var now = new DateTime.now();

    if (_active.isEmpty) {
      _active.add(e);
      next = e;
    } else {
      ind = getTsIndex(_active, nextTs);
      _active.insert(ind, e);
      next = _active.first;
    }

    if (!isSet) _setTimer(now);
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
      _checkActive(e);
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

  /// Sets up the Timer for the next call including properly setting the isEnd
  /// flag. This handles cancelling any existing timer and resetting the timer
  /// along with the appropriate flags
  void _setTimer([DateTime now]) {
    now ??= new DateTime.now();
    if (_timer != null && _timer.isActive) _timer.cancel();

    var nextTs = _getNextTs();
    if (current == null) {
      // no timer to set.
      if (nextTs == null) return;

      // Beginning of next.
      _isEnd = false;
      _timer = new Timer(nextTs.difference(now), _timerEnd);
      return;
    }

    var endDur = current.timeRange.remaining(now);
    if (nextTs == null) {
      // End timer for existing
      _isEnd = true;
      _timer = new Timer(endDur, _timerEnd);
      return;
    }

    var until = nextTs.difference(now);
    if (endDur < until) {
      _isEnd = true;
      _timer = new Timer(endDur, _timerEnd);
    } else {
      _isEnd = false;
      _timer = new Timer(until, _timerEnd);
    }
  }

  /// Delete this schedule. Cancels timers, clears event queues, closes stream.
  void delete() {
    if (_timer.isActive) _timer.cancel();
    if (!_controller.isClosed) _controller.close();
    _active.length = 0;
    events.length = 0;
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
      var nextTs = current.timeRange.nextTs();
      if (nextTs == null) {
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

  /// Remove the specified [Event] from the currently active Events, if
  /// appropriate, reinsert it into the correct place.
  void _checkActive(Event e) {
    var nextTs = e.timeRange.nextTs();
    _active.remove(e);
    // Should not have anymore instances, just remove it.
    if (e.timeRange.frequency == Frequency.Single || nextTs == null) return;

    var ind = getTsIndex(_active, nextTs);
    _active.insert(ind, e);
  }
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
