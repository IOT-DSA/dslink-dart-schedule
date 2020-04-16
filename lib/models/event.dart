import 'timerange.dart';

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