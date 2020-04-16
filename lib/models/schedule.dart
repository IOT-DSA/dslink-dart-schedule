import 'dart:async';

import 'event.dart';

/// A schedule contains a default value (may be null) and a list of 0 or more
/// events that occur during that schedule.
class Schedule {
  /// Internal reference name for the schedule.
  String name;
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