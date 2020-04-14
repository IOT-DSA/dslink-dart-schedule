import 'dart:async';

import 'timerange.dart';

/// A schedule contains a default value (may be null) and a list of 0 or more
/// events that occur during that schedule.
class Schedule {
  /// The schedule will provide this Event when no event is active.
  Event defaultValue;
  /// List of events that make up the schedule.
  List<Event> events;
  /// The event that is currently active.
  Event current;
  /// Next event scheduled to be active.
  Event next;
  /// Stream of values from the schedule which are generated at the appropriate
  /// time.
  Stream<Object> get values => _controller.stream;

  Timer _timer;
  StreamController<Object> _controller;

// Should schedules provide the values with a stream? Stream of values
// Broadcast stream, since that won't block when not listened.
}

/// An Event takes place at a specified [TimeRange] (A single moment, a simple
/// range, or a recurring [Frequency]). It will have a specific value which is
/// triggered when an event is "active" (Within the TimeRange). An event may
/// also have a specific [priority] or it may be flagged as a special event which
/// supersedes any other events on that day.
class Event {
  /// Priority level 0 - 9. 0 Is no priority specified. 1 is highest 9 is lowest.
  /// An event will only start
  int priority;
  /// specialEvent indicates if this event should supersede all other events
  /// for that day. Not to be confused with a higher priority, which will allow
  /// the other events to still occur as long as they do not over-lap.
  bool isSpecial;
  /// Value to be set when event is active
  Object value;
  /// The Date and Time range, and frequency over that period, the event should
  /// occur.
  TimeRange timeRange;

  Event(this.timeRange, this.value, {this.isSpecial: false, this.priority: 0});
}