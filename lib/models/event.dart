import 'dart:math' show Random;
import 'timerange.dart';

/// An Event takes place at a specified [TimeRange] (A single moment, a simple
/// range, or a recurring [Frequency]). It will have a specific value which is
/// triggered when an event is "active" (Within the TimeRange). An event may
/// also have a specific [priority] or it may be flagged as a special event which
/// supersedes any other events on that day.
class Event {
  /// Display name for the event.
  String name;
  /// Internal identifier for the event.
  String id;
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
  final TimeRange timeRange;

  Event(this.name, this.timeRange, this.value,
      {this.isSpecial: false, this.priority: 0, this.id: null}) {
    if (id == null) id = generateId();
  }

  static const String _name = 'name';
  static const String _id = 'id';
  static const String _priority = 'priority';
  static const String _special = 'special';
  static const String _value = 'value';
  static const String _time = 'timeRange';

  /// Create a new Event from a json map that was previously exported with [toJson]
  factory Event.fromJson(Map<String, dynamic> map) {
    String name = map[_name];
    String id = map[_id];
    int priority = map[_priority];
    bool special = map[_special];
    Object value = map[_value];
    TimeRange tr = new TimeRange.fromJson(map[_time]);

    return new Event(name, tr, value,
        isSpecial: special, priority: priority, id: id);
  }

  /// Export the Event to a json map.
  Map<String, dynamic> toJson() => {
    _name: name,
    _id: id,
    _priority: priority,
    _special: isSpecial,
    _value: value,
    _time: timeRange.toJson()
  };
}

/// Create a random ID String of Letters (upper and lowercase) and numbers.
/// Optionally you may specify a length for the string, which defaults to 50.
String generateId({int length: 50}) {
  var buff = new StringBuffer();
  var rand = new Random();

  for (var i = 0; i < length; i++) {
    if (rand.nextBool()) {
      // A = 65, Z = 90. Add 32 for lowercase.
      var cc = rand.nextInt(26) + 65;
      if (rand.nextBool()) cc += 32;
      buff.writeCharCode(cc);
    } else {
      buff.write(rand.nextInt(10));
    }
  }

  return buff.toString();
}