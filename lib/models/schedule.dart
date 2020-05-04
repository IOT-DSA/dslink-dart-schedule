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
  void set defaultValue(Object value) {
    _defaultValue = value;
    // Send notification of change of defaultValue
    if (current == null) _controller.add(value);
  }
  Object get defaultValue => _defaultValue;
  Object _defaultValue;
  /// List of events that make up the schedule.
  List<Event> events;
  /// The event that is currently active.
  Event current;
  /// Next event scheduled to be active.
  Event next;
  /// Stream of values from the schedule which are generated at the appropriate
  /// time.
  Stream<Object> get values => _controller.stream;

  Object get currentValue => current != null ? current.value : _defaultValue;

  // These are used for to/from json encoding
  static const String _name = 'name';
  static const String _value = 'value';
  static const String _events = 'events';

  Timer _timer;
  StreamController<Object> _controller;
  List<Event> _active;
  bool _isEnd = false; // When timer ends revert to default rather than start new
  // Flag to see if the active list has changed. Used in getNextTs to track cache.
  bool _hasChanged = false;

  /// Create a new schedule with the specified name, and specified defaultValue.
  Schedule(this.name, this._defaultValue) {
    events = new List<Event>();
    _active = new List<Event>();
    _controller = new StreamController.broadcast(onListen: _onListen);
  }

  /// Create a new Schedule from a json map of a previously exported scheduled.
  Schedule.fromJson(Map<String, dynamic> map) {
    name = map[_name];
    _defaultValue = map[_value];
    var eList = map[_events] as List<Map>;

    events = new List<Event>();
    _active = new List<Event>();
    _controller = new StreamController.broadcast(onListen: _onListen);
    for (var e in eList) {
      add(new Event.fromJson(e));
    }
  }

  /// Export this schedule to a json encode-able map.
  Map<String, dynamic> toJson() => {
    _name: name,
    _value: defaultValue,
    _events: events.map((Event e) => e.toJson()).toList()
  };

  /// Add an event to this schedule.
  void add(Event e) {
    bool isSet = false;
    var nextTs = e.timeRange.nextTs();

    var ind = getTsIndex(events, nextTs);
    events.insert(ind, e);

    // Check if it should become active right now.
    var now = new DateTime.now();
    if (e.timeRange.includes(now)) {
      _setCurrent(getPriority(current, e));
      isSet = true; // Prevent redundant setting timer.
    }

    // Not current, and all events took place in the past.
    if (nextTs == null) return;

    _hasChanged = true;
    if (_active.isEmpty) {
      _active.add(e);
    } else {
      ind = getTsIndex(_active, nextTs);
      _active.insert(ind, e);
    }
    // Handles setting up the next value
    getNextTs(now);

    if (!isSet) _setTimer(now);
  }

  /// Remove the event matching the specified ID.
  void remove(String id) {
    var ind = 0;
    for (; ind < events.length; ind++) {
      if (events[ind].id == id) break;
    }

    if (ind == events.length) return;
    var evnt = events.removeAt(ind);
    _active.remove(evnt);

    _hasChanged = true;
    if (evnt == current) _setCurrent(null);
    if (evnt == next) getNextTs();
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

    var nextTs = getNextTs();
    if (e == null) {
      if (nextTs == null) { next = null; return; }

      // No current Event, create timer until next event.
      _timer = new Timer(nextTs.difference(now), _timerEnd);
      _isEnd = false;
      return;
    }

    var dur = e.timeRange.remaining(now) ?? e.timeRange.period;
    var end = now.add(dur);
    // no more events after this currently, so start timer until the end
    // of the current period.
    if (nextTs == null || nextTs.isAfter(end)) {
      _timer = new Timer(dur, _timerEnd);
      _isEnd = true;
    } else {
      // Next timeStamp is before end of current.
      _timer = new Timer(nextTs.difference(now), _timerEnd);
      _isEnd = false;
    }
  }

  // Returns the DateTime stamp of the next event. This also has a side effect
  // that will assign the next Event to the `next` value of the Schedule
  DateTime getNextTs([DateTime moment]) {
    if (_active.isEmpty) return null;
    moment ??= new DateTime.now();

    var isSpecial = getSpecialOn(moment) != -1;

    // Don't use cached values on special days
    if (!_hasChanged && !isSpecial) {
      var nNextTs = next?.timeRange?.nextTs(moment);
      if (nNextTs != null && getSpecialOn(nNextTs) == -1)
        return next?.timeRange?.nextTs(moment);
    }

    next = null;

    _active.sort((Event a, Event b) {
      var tsA = a.timeRange.nextTs(moment);
      var tsB = b.timeRange.nextTs(moment);
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;
      return tsA.compareTo(b.timeRange.nextTs(moment));
    });

    var n = _active.first;
    var nextTs = n.timeRange.nextTs(moment);
    if (nextTs == null) return null;

    // Not a special day today. Just get the next event.
    if (!isSpecial) {
      // Make sure next event is today, or is special itself.
      if (sameDayOfYear(moment, nextTs) || n.isSpecial) {
        next = n;
        _hasChanged = false;
        return nextTs;
      }

      var ind = getSpecialOn(nextTs);
      // No special events on that day.
      if (ind == -1) {
        next = n;
        _hasChanged = false;
        return nextTs;
      } else {
        // There's a special event on that day, so return that which may not be
        // the "first" event.
        next = events[ind];
        _hasChanged = false;
        return next.timeRange.nextTs();
      }
    }

    // Today is a special day, Next event must be special or tomorrow.
    if (n.isSpecial) {
      next = n;
      _hasChanged = false;
      return nextTs;
    }

    var specials = _active.where((Event e) => e.isSpecial);

    for (var sp in specials) {
      var ts = sp.timeRange.nextTs();
      if (ts == null) continue;
      // If it's not the same day, don't bother checking the next ones, they
      // shouldn't be either since it's sorted by NextTS
      if (!sameDayOfYear(moment, ts)) break;

      next = sp;
      _hasChanged = false;
      return ts;
    }

    // No specials left for today. So start figuring out the next timestamp
    // at midnight.
    var nextDay = new DateTime(moment.year, moment.month, moment.day + 1);
    return getNextTs(nextDay);
  }

  /// Sets up the Timer for the next call including properly setting the isEnd
  /// flag. This handles cancelling any existing timer and resetting the timer
  /// along with the appropriate flags
  void _setTimer([DateTime now]) {
    now ??= new DateTime.now();
    if (_timer != null && _timer.isActive) _timer.cancel();

    var nextTs = getNextTs();
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
    if (_timer != null && _timer.isActive) _timer.cancel();
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
    // Check and see if any events should be removed from active.
    _active.removeWhere((Event e) => e.timeRange.nextTs() == null);
    _hasChanged = true;

    // Set back to default.
    if (_isEnd) {
      _setCurrent(null);
      return;
    }

    if (next == null) {
      var nextTs = getNextTs();
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

  /// Check if there is a special event on the specified date. Returns the index
  /// of the event if true, and returns -1 if not found.
  int getSpecialOn(DateTime date) {
    int i;
    for (i = 0; i < events.length; i++) {
      var evt = events[i];
      if (evt.isSpecial && evt.timeRange.sameDay(date)) return i;
    }
    return -1;
  }

  /// Update the value for an event. Handled from here that way if an event
  /// is currently active the new value will be pushed immediately.
  void updateEventValue(String id, Object value) {
    var e = events.firstWhere((Event e) => e.id == id, orElse: () => null);
    if (e == null) {
      throw new ArgumentError.value(id, 'id',
          'Unable to locate event with specified ID');
    }

    e.value = value;
    if (current?.id == e.id) {
      _controller.add(value);
    }
  }
}

/// Get the index into which an event at the specified DateTime dt should be
/// inserted into the list.
int getTsIndex(List<Event> list, DateTime dt) {
  var ind = list.length;
  if (dt == null) return ind;

  var now = new DateTime.now();
  for (int i = 0; i < list.length; i++) {
    var eTs = list[i].timeRange.nextTs(now);
    if (eTs == null || eTs.isBefore(dt)) continue;

    ind = i;
    break;
  }

  return ind;
}
