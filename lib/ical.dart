library dslink.schedule.ical;

import "dart:async";
import "dart:convert";
import "dart:collection";

import "calendar.dart";
import "utils.dart";
import "tz.dart";

import "package:timezone/timezone.dart";

import "package:dslink/utils.dart" show generateBasicId, generateToken;
import "package:dslink/common.dart" show unspecified;

class CalendarObject {
  String type;
  CalendarObject parent;
  Map<String, dynamic> properties = {};

  @override
  String toString() => "CalendarObject(${type}, ${properties})";

  Map toJSON() {
    var out = {};
    var props = {};
    for (var key in properties.keys) {
      var value = properties[key];
      props[key] = value;
    }
    out["@type"] = type;
    out["@properties"] = props;
    return out;
  }

  Map getTimezoneLookupTable() {
    var map = {};
    var tzinfo = properties["VTIMEZONE"];
    if (tzinfo is! List) tzinfo = [tzinfo];
    bool isDaylightSavings = false;
    var now = new DateTime.now();
    if (now.timeZoneName.contains("DT")) {
      isDaylightSavings = true;
    }

    for (CalendarObject x in tzinfo) {
      var id = x.properties["TZID"];
      if (id == null) continue;
      CalendarObject me = x.properties["STANDARD"];
      if (me == null) {
        me = x;
      }

      if (isDaylightSavings && x.properties["DAYLIGHT"] != null) {
        me = x.properties["DAYLIGHT"];
      }

      if (me is List) {
        me = (me as List).first;
      }

      map[id] = me.properties["TZOFFSETTO"];
    }

    return map;
  }
}

Map tokenizePropertyList(String input) {
  var props = input.split(";");
  var out = {};
  for (var prop in props) {
    var parts = prop.split("=");
    var key = parts[0];
    var value = parts.skip(1).join("=");
    out[key] = value;
  }
  return out;
}

List tokenizeCalendar(String input) {
  input = input.replaceAll("\r\n", "\n");

  var lines = input.split("\n");
  var out = [];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.trim().isEmpty) {
      continue;
    }

    if (i < (lines.length - 1)) {
      var x = i + 1;
      while (x < lines.length && lines[x].startsWith(" ")) {
        line += lines[x].trimLeft();
        x++;
        i++;
      }
    }

    var parts = line.split(":");
    var head = parts[0];
    var tail = parts.skip(1).join(":");

    if (tail.contains(";") || tail.contains("=")) {
      tail = tokenizePropertyList(tail);
    }

    if (head.contains(";") && head.contains("=")) {
      var heads = head.split(";");
      var first = heads.first;
      var n = [];
      if (!first.contains("=")) {
        n.add(first);
        head = heads.skip(1).join(";");
        head = tokenizePropertyList(head);
        n.add(head);
      } else {
        head = tokenizePropertyList(head);
        n = head;
      }

      head = n;
    }

    out.add([head, tail]);
  }
  return out;
}

CalendarObject parseCalendarObjects(List input) {
  CalendarObject root = new CalendarObject();
  CalendarObject obj;
  for (List x in input) {
    if (x[0] == "BEGIN") {
      if (obj != null) {
        var temp = obj;
        obj = new CalendarObject();
        obj.type = x[1];
        obj.parent = temp;
        if (!temp.properties.containsKey(obj.type)) {
          temp.properties[obj.type] = [];
        }
        temp.properties[obj.type].add(obj);
      } else {
        root.type = x[1];
        obj = root;
      }
    } else if (x[0] == "END") {
      obj = obj.parent;
    } else {
      var typ = x[0];
      if (typ is List) {
        var type = typ[0];
        if (!obj.properties.containsKey(type)) {
          obj.properties[type] = [];
        }
        var val = parseCalendarValue({
          "metadata": typ[1],
          "value": x[1]
        }, root);
        obj.properties[type].add(val);
      } else {
        var key = x[0];
        var val = x[1];
        if (obj.properties.containsKey(key)) {
          var l = obj.properties[key];
          if (l is List) {
            l.add(val);
          } else {
            obj.properties[key] = [obj.properties[key], val];
          }
        } else {
          var out = {};
          if (val is Map) {
            for (var n in val.keys) {
              out[n] = parseCalendarValue(val[n], root);
            }
            val = out;
          } else {
            val = parseCalendarValue(val, root);
          }
          obj.properties[key] = val;
        }
      }
    }
  }
  return root;
}

dynamic parseCalendarValue(input, CalendarObject root) {
  String str;
  dynamic val;
  if (input is Map) {
    str = input["value"];
  } else {
    str = input;
  }
  val = str;

  try {
    if (str[8] == "T") {
      String offset;
      if (input is Map && input["metadata"] is Map && input["metadata"]["TZID"] != null) {
        String name = input["metadata"]["TZID"];
        offset = root.getTimezoneLookupTable()[name];
      }
      val = parseCalendarDate(str, offset);
    }
  } catch (e) {
  }

  try {
    val = num.parse(str);
  } catch (e) {}

  if (input is Map) {
    input["value"] = val;
    return input;
  } else {
    return val;
  }
}

dynamic parseCalendarDate(String input, [offset]) {
  if (input.contains(",")) {
    return input.split(",").map((x) => parseCalendarDate(x, offset)).toList();
  } else {
    return DateTime.parse(input);
  }
}

enum RuleFrequency {
  YEARLY,
  MONTHLY,
  WEEKLY,
  DAILY,
  HOURLY,
  MINUTELY,
  SECONDLY
}

enum Weekday {
  MONDAY,
  TUESDAY,
  WEDNESDAY,
  THURSDAY,
  FRIDAY,
  SATURDAY,
  SUNDAY
}

enum Month {
  JANUARY,
  FEBRUARY,
  MARCH,
  APRIL,
  MAY,
  JUNE,
  JULY,
  AUGUST,
  SEPTEMBER,
  OCTOBER,
  NOVEMBER,
  DECEMBER
}

Weekday iCalWeekdayToEnum(String input) {
  if (input == null) {
    return null;
  }

  input = input.trim().toUpperCase();
  var map = const <String, Weekday>{
    "SU": Weekday.SUNDAY,
    "MO": Weekday.MONDAY,
    "TU": Weekday.TUESDAY,
    "WE": Weekday.WEDNESDAY,
    "TH": Weekday.THURSDAY,
    "FR": Weekday.FRIDAY,
    "SA": Weekday.SATURDAY
  };

  if (map.containsKey(input)) {
    return map[input];
  }
  return null;
}

class Rule extends IterableBase {
  final RuleFrequency frequency;
  DateTime start;
  DateTime until;
  int count;
  int interval = 1;
  List<Weekday> byWeekday = [];
  List<Month> byMonth = [];
  List<int> bySetPos = [];
  List<int> byHour = [];
  List<int> byMinute = [];
  List<int> bySecond = [];

  Rule(this.frequency);

  bool fitsWeekday(DateTime time) {
    for (var w in byWeekday) {
      if (w.index + 1 == time.weekday) {
        return true;
      }
    }
    return false;
  }

  bool fitsMonth(DateTime time) {
    for (var m in byMonth) {
      if (m.index + 1 == time.month) {
        return true;
      }
    }
    return false;
  }

  Duration getFrequencyDuration() {
    if (frequency == RuleFrequency.DAILY) {
      return new Duration(days: interval);
    } else if (frequency == RuleFrequency.HOURLY) {
      return new Duration(hours: interval);
    } else if (frequency == RuleFrequency.MINUTELY) {
      return new Duration(minutes: interval);
    } else if (frequency == RuleFrequency.SECONDLY) {
      return new Duration(seconds: interval);
    } else if (frequency == RuleFrequency.WEEKLY) {
      return new Duration(days: 7 * interval);
    } else if (frequency == RuleFrequency.YEARLY) {
      return new Duration(days: 365 * interval);
    } else {
      throw new Exception("Unknown Frequency");
    }
  }

  @override
  Iterator get iterator => new RuleTimeIterator(this);
}

class RuleTimeIterator extends Iterator<EventTiming> {
  final Rule rule;

  RuleTimeIterator(this.rule);

  EventTiming _lastTime;
  EventTiming _previousTime;

  EventTiming next([EventTiming lastTime]) {
    var saved = false;
    if (lastTime == null) {
      lastTime = _lastTime;
      saved = true;
    }

    EventTiming space = _next(lastTime);

    if (space == null) {
      return space;
    }

    var i = 1;

    if (rule.byWeekday.isNotEmpty) {
      while (space != null && !rule.fitsWeekday(space.time)) {
        space = _next(space);
      }
    }

    if (rule.byMonth.isNotEmpty) {
      while (space != null && !rule.fitsMonth(space.time)) {
        space = _next(space);
      }
    }

    if (rule.byHour.isNotEmpty) {
      while (space != null && !rule.byHour.contains(space.time.hour)) {
        space = _next(space);
      }
    }

    if (rule.byMinute.isNotEmpty) {
      while (space != null && !rule.byMinute.contains(space.time.minute)) {
        space = _next(space);
      }
    }

    if (rule.bySecond.isNotEmpty) {
      while (space != null && !rule.bySecond.contains(space.time.second)) {
        space = _next(space);
      }
    }

    if (rule.bySetPos.isNotEmpty) {
      while (space != null && !rule.bySetPos.contains(i)) {
        space = _next(space);
        i++;
      }
    }

    if (space != null) {
      lastTime = space;
    }

    if (saved) {
      _previousTime = _lastTime;
      _lastTime = lastTime;
      _count++;
    }

    return space;
  }

  EventTiming _next([EventTiming last]) {
    EventTiming space;

    if (rule.count != null && _count == rule.count) {
      return null;
    }

    var start = rule.start;
    DateTime day = last == null ? null : last.time;
    if (day == null) day = start.subtract(rule.getFrequencyDuration());
    day = day.add(rule.getFrequencyDuration());
    space = new EventTiming(day);

    if (rule.until != null && space.time.isAfter(rule.until)) {
      space = null;
    }

    return space;
  }

  int _count = 0;

  @override
  EventTiming current;

  EventTiming future;

  @override
  bool moveNext() {
    current = next();
    return current != null;
  }

  bool movePrevious() {
    if (_previousTime == null) {
      return false;
    }
    current = next(_previousTime);
    _count--;
    return current != null;
  }

  RuleTimeIterator clone() {
    var iter = new RuleTimeIterator(rule);
    iter._count = _count;
    iter._previousTime = _previousTime;
    iter._lastTime = _lastTime;
    return iter;
  }
}

class EventTiming {
  final DateTime time;

  EventTiming(this.time);

  @override
  String toString() => "Event(${time})";
}

List<Event> loadEvents(String input) {
  var tokens = tokenizeCalendar(input);
  var root = parseCalendarObjects(tokens);
  var vevents = root.properties["VEVENT"];

  if (vevents == null) {
    vevents = [];
  }

  var events = <Event>[];
  for (CalendarObject x in vevents) {
    var summary = x.properties["SUMMARY"];
    var description = x.properties["DESCRIPTION"];
    var start = x.properties["DTSTART"];
    var end = x.properties["DTEND"];
    var rrule = x.properties["RRULE"];

    if (rrule == null) {
      rrule = {
        "FREQ": "DAILY",
        "UNTIL": end
      };
    }

    var e = new Event();
    e.summary = summary;
    e.description = description;
    e.start = getDateTimeFromObject(start);
    e.end = getDateTimeFromObject(end);
    e.rrule = rrule;
    e.parseRule();
    events.add(e);
  }

  return events;
}

DateTime getDateTimeFromObject(obj) {
  if (obj is List) {
    obj = obj.first;
  }

  if (obj is DateTime) {
    return obj;
  } else if (obj is Map && obj["value"] is DateTime) {
    return obj["value"];
  } else {
    return null;
  }
}

class Event {
  DateTime start;
  DateTime end;
  String summary;
  dynamic description;
  Rule rule;
  Map rrule;

  Duration get duration => start.difference(end).abs();

  @override
  String toString() {
    var lines = [
      "Event {",
      "  Start: ${start}",
      "  End: ${end}",
      "  Summary: ${summary}",
      "  Description: ${description}",
      "}"
    ];

    return lines.join("\n");
  }

  EventDescription describe() {
    var e = new EventDescription(summary, extractValue());
    e.isRecurring = rrule == null || rrule.isEmpty;
    if (!e.isRecurring) {
      e.start = start;
      e.end = end;
    }

    e.duration = duration;

    return e;
  }

  dynamic _value = unspecified;

  dynamic extractValue() {
    if (_value != unspecified) {
      return _value;
    }

    if (description is Map) {
      if (description["value_json"] != null) {
        var val = description["value_json"];
        if (val is String) {
          val = const JsonDecoder().convert(val);
        }
        return _value = val;
      } else {
        return _value = description["value"];
      }
    } else if (description is String) {
      var matches = VALUE_REGEX.allMatches(description);
      var isJson = false;
      if (matches.isEmpty) {
        matches = VALUE_JSON_REGEX.allMatches(description);
        isJson = true;
      }

      if (matches.isEmpty) {
        return _value = null;
      }
      var content = matches.first.group(1);

      if (isJson) {
        return _value = const JsonDecoder().convert(content);
      } else {
        return _value = content;
      }
    } else {
      return _value = null;
    }
  }

  void parseRule() {
    var freqName = rrule["FREQ"];

    var freq = const <String, RuleFrequency>{
      "DAILY": RuleFrequency.DAILY,
      "SECONDLY": RuleFrequency.SECONDLY,
      "YEARLY": RuleFrequency.YEARLY,
      "MONTHLY": RuleFrequency.MONTHLY,
      "HOURLY": RuleFrequency.HOURLY,
      "MINUTELY": RuleFrequency.MINUTELY,
      "WEEKLY": RuleFrequency.WEEKLY
    }[freqName];

    rule = new Rule(freq);

    if (rrule["UNTIL"] is DateTime) {
      rule.until = rrule["UNTIL"];
    }

    dynamic getListFromRule(String name) {
      var value = rrule[name];

      if (value == null) {
        return null;
      }

      if (value is List) {
        return value;
      }

      if (value is num) {
        return value;
      }

      if (value is! String) {
        return null;
      }

      var parts = value.split(",");
      var list = [];
      for (var x in parts) {
        x = parseInputValue(x);
        list.add(x);
      }
      return list;
    }

    var bySetPos = getListFromRule("BYSETPOS");
    var byMonth = getListFromRule("BYMONTH");
    var byMinute = getListFromRule("BYMINUTE");
    var byHour = getListFromRule("BYHOUR");
    var bySecond = getListFromRule("BYSECOND");
    var byWeekday = rrule["BYDAY"];

    void addToList(List a, b) {
      if (b is List) {
        a.addAll(b);
      } else {
        a.add(b);
      }
    }

    if (bySetPos is num || bySetPos is List) {
      addToList(rule.bySetPos, bySetPos);
    }

    if (byMonth is num || byMonth is List) {
      addToList(rule.byMonth, byMonth);
    }

    if (byHour is num || byHour is List) {
      addToList(rule.byHour, byHour);
    }

    if (byMinute is num || byMinute is List) {
      addToList(rule.byMinute, byMinute);
    }

    if (bySecond is num || bySecond is List) {
      addToList(rule.bySecond, bySecond);
    }

    if (byWeekday is String) {
      List<Weekday> indexes = byWeekday
          .split(",")
          .map(iCalWeekdayToEnum)
          .where((x) => x != null)
          .toList();
      rule.byWeekday.addAll(indexes);
    }

    if (rrule["INTERVAL"] is num) {
      rule.interval = rrule["INTERVAL"].toInt();
    }

    if (rrule["COUNT"] is num) {
      rule.count = rrule["COUNT"].toInt();
    }

    rule.start = start;
  }
}

class EventInstance {
  final Event event;

  EventInstance(this.event) {
    if (event.rule == null) {
      event.parseRule();
    }
    iterator = event.rule.iterator;
  }

  RuleTimeIterator iterator;
}

class ICalendarProvider extends CalendarProvider {
  final List<EventInstance> events;

  ICalendarProvider(this.events);

  @override
  ValueAtTime current(ValueCalendarState state) {
    var queue = <EventInstance, ValueAtTime>{};
    for (var e in events) {
      var cloned = e.iterator.clone();
      var value = e.event.extractValue();
      thisEvent: while (cloned.moveNext()) {
        var v = new ValueAtTime(
            cloned.current.time,
            value,
            e.event.duration,
            e.event.describe()
        );

        if (v.hasAlreadyHappened) {
          continue thisEvent;
        }
        queue[e] = v;
        break thisEvent;
      }
    }

    var list = queue.values.toList();

    if (list.isEmpty) {
      return null;
    }

    list.sort((a, b) => b.time.compareTo(a.time));
    var last = list.last;

    for (var k in queue.keys) {
      if (queue[k] == last) {
        k.iterator.moveNext();
      }
    }

    queued = last;

    return last;
  }

  ValueAtTime queued;

  @override
  ValueAtTime next(ValueCalendarState state) {
    var queue = <EventInstance, ValueAtTime>{};
    for (var e in events) {
      var cloned = e.iterator.clone();
      thisEvent: while (cloned.moveNext()) {
        var value = e.event.extractValue();
        var v = new ValueAtTime(
            cloned.current.time,
            value,
            e.event.duration,
            e.event.describe()
        );

        if (v.hasAlreadyHappened) {
          continue thisEvent;
        }
        queue[e] = v;
        break thisEvent;
      }
    }

    var list = queue.values.toList();

    if (list.isEmpty) {
      return null;
    }

    list.sort((a, b) => b.time.compareTo(a.time));
    var last = list.last;

    if (queued != null && queued.isHappeningNow && queued.endsAt.isBefore(last.time)) {
      return new ValueAtTime(
          queued.endsAt,
          state.defaultValue.value,
          queued.endsAt.difference(last.time).abs(),
          state.defaultValue.description
      );
    }

    if (queued != null && !queued.hasAlreadyHappened) {
      return queued;
    }

    return last;
  }

  @override
  List<EventDescription> listEvents() {
    return events.map((x) {
      return x.event.describe();
    }).toList();
  }
}

Future<String> generateCalendar(String name) async {
  var lines = [
    "BEGIN:VCALENDAR",
    "PRODID:-//Distributed Services Architecture//Schedule DSLink//EN",
    "VERSION:2.0",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:${name}"
  ];

  var zone = await findTimezoneOnSystem();

  if (zone == null) {
    zone = UTC;
  }

  lines.add(buildICalTimezoneSection(zone));

  return lines.join("\n");
}

void serializeCalendar(input, StringBuffer buffer, [String keyName]) {
  if (keyName != null) {
    if (input is Map) {
      var meta = serializeCalendarValue(input["metadata"]);
      var val = serializeCalendarValue(input["value"]);
      if (meta.isNotEmpty) {
        meta = ";${meta}";
      }

      buffer.writeln("${keyName}${meta}:${val}");
      return;
    }
  }

  if (input is CalendarObject) {
    buffer.writeln("BEGIN:${input.type}");
    for (String key in input.properties.keys) {
      var value = input.properties[key];
      if (value is List) {
        for (var x in value) {
          serializeCalendar(x, buffer, key);
        }
      } else {
        buffer.writeln("${key}:${serializeCalendarValue(value)}");
      }
    }
    buffer.writeln("END:${input.type}");
  } else {
    buffer.writeln(input);
  }
}

class StoredEvent {
  final String name;
  final dynamic value;
  final TimeRange timeRange;
  final Map rule;

  String id;

  StoredEvent(this.name, this.value, this.timeRange, [this.rule]);

  CalendarObject toCalendarObject() {
    var object = new CalendarObject();
    object.type = "VEVENT";
    object.properties["DTSTART"] = formatICalendarTime(timeRange.start);
    object.properties["DTEND"] = formatICalendarTime(timeRange.end);
    var json = const JsonEncoder().convert(value);
    object.properties["DESCRIPTION"] = "value_json=${json}";
    object.properties["TRANSP"] = "OPAQUE";
    object.properties["SUMMARY"] = name;
    if (id != null) {
      object.properties["UID"] = id;
    }

    if (rule != null && rule.isNotEmpty) {
      object.properties["RRULE"] = rule;
    }
    return object;
  }

  void assignID() {
    id = generateToken();
  }

  Map encode() {
    if (id == null) {
      assignID();
    }

    var map = {
      "name": name,
      "value": value,
      "start": timeRange.start.toIso8601String(),
      "end": timeRange.end.toIso8601String(),
      "rule": rule,
      "id": id
    };
    return map;
  }

  static StoredEvent decode(Map input) {
    if (input is! Map) return null;
    String name = input["name"];
    String id = input["id"];
    dynamic value = input["value"];
    var start = input["start"];
    var end = input["end"];
    Map rule = input["rule"];

    if (rule is! Map) {
      rule = {};
    }

    {
      var tmp = rule;
      rule = {};
      for (String key in tmp.keys) {
        var next = key.toUpperCase();
        var value = tmp[key];
        if (next == "FREQUENCY" || next == "FREQ") {
          next = "FREQ";
          value = value.toString().toUpperCase();
        }
        rule[next] = value;
      }
    }

    if (start is String) {
      start = DateTime.parse(start);
    } else if (start is int) {
      start = new DateTime.fromMillisecondsSinceEpoch(start);
    }

    if (end is String) {
      end = DateTime.parse(end);
    } else if (start is int) {
      end = new DateTime.fromMillisecondsSinceEpoch(end);
    }

    var range = new TimeRange(start, end);

    var event = new StoredEvent(name, value, range, rule);
    event.id = id;
    if (event.id == null) {
      event.assignID();
    }
    return event;
  }
}

String serializeCalendarValue(input) {
  if (input is DateTime) {
    return formatICalendarTime(input);
  } else if (input is Map) {
    var out = [];
    for (var key in input.keys) {
      out.add("${key}=${serializeCalendarValue(input[key])}");
    }
    return out.join(";");
  } else {
    return input.toString();
  }
}

final RegExp VALUE_REGEX = new RegExp(r"value=([^\n]+)");
final RegExp VALUE_JSON_REGEX = new RegExp(r"value_json=([^\n]+)");
