import 'dart:async';

import 'package:dslink/dslink.dart';

import 'package:dslink_schedule/schedule.dart';
import 'package:dslink_schedule/utils.dart' show parseInputValue;
import 'package:dslink_schedule/models/timerange.dart';

import 'common.dart';

class AddSingleEvent extends ScheduleChild {
  static const String isType = 'addSingleEvent';
  static const String pathName = 'add_single_event';

  static const String _name = 'name';
  static const String _value = 'value';
  static const String _dateRange = 'dateRange';
  static const String _isSpecial = 'isSpecial';
  static const String _priority = 'priority';

  static Map<String, dynamic> def() => {
    r'$name': 'Add Event',
    r'$is': isType,
    r'$invokable': 'write',
    r'$params': [
      {
        'name': _name,
        'type': 'string',
        'placeholder': 'Activate Light',
        'description': 'Identifiable name for the event.'
      },
      {
        'name': _value,
        'type': 'dynamic',
        'description': 'Value when event is triggered'
      },
      {
        'name': _dateRange,
        'type': 'string',
        'editor': 'daterange',
        'description': 'Start and end date range of the event.'
      },
      {
        'name': _isSpecial,
        'type': 'bool',
        'default': 'false',
        'description': 'Flag indicating if this is considered a special event'
      },
      {
        'name': _priority,
        'type': 'number',
        'editor': 'int',
        'min': 0,
        'max': 9,
        'default': 0,
        'description': 'Event priority. 0 is none specified; 1 is highest; 9 is lowest.'
      }
    ]
  };

  final LinkProvider _link;
  AddSingleEvent(String path, this._link) : super(path);

  @override
  void onInvoke(Map<String, dynamic> params) {
    var name = params[_name] as String;
    var sched = getSchedule();
    if (sched.schedule.events.contains((Event e) => e.name == name)) {
      throw new ArgumentError.value(name, _name, 'An event by that name already exists');
    }

    var val = parseInputValue(params[_value]);
    var spec = params[_isSpecial] ?? false;
    var pri = params[_priority] ?? 0;
    var dateStr = params[_dateRange] as String;
    if (!dateStr.contains(r'/')) {
      throw new ArgumentError.value(dateStr, _dateRange,
          'Unexpected date range. Should be in the format <startDateTime>/<endDateTime>');
    }

    var date = dateStr.split(r'/');
    var startDate = DateTime.parse(date[0]);
    var endDate = DateTime.parse(date[1]);

    var tr = new TimeRange.single(startDate, endDate);
    var evnt = new Event(name, tr, val, isSpecial: spec, priority: pri);
    sched.addEvent(evnt);

    var en = provider.addNode('${parent.path}/${evnt.id}', EventsNode.def(evnt)) as EventsNode;
    if (en != null) {
      en.event = evnt;
    }
    _link.save();
  }
}

class AddMomentEvent extends ScheduleChild {
  static const String pathName = 'add_moment_event';
  static const String isType = 'addMomentEvent';

  static const String _date = 'dateTime';
  static const String _value = 'value';
  static const String _name = 'name';
  static const String _priority = 'priority';
  static const String _isSpecial = 'isSpecial';

  static Map<String, dynamic> def() => {
    r'$name': 'Add Moment Event',
    r'$is': isType,
    r'$invokable': 'write',
    r'$params': [
      {
        'name': _name,
        'type': 'string',
        'placeholder': 'Activate Light',
        'description': 'Identifiable name for the event.'
      },
      {
        'name': _value,
        'type': 'dynamic',
        'description': 'Value when event is triggered'
      },
      {
        'name': _date,
        'type': 'string',
        'editor': 'daterange',
        'description': 'Start date and time of the event.'
      },
      {
        'name': _isSpecial,
        'type': 'bool',
        'default': 'false',
        'description': 'Flag indicating if this is considered a special event'
      },
      {
        'name': _priority,
        'type': 'number',
        'editor': 'int',
        'min': 0,
        'max': 9,
        'default': 0,
        'description': 'Event priority. 0 is none specified; 1 is highest; 9 is lowest.'
      }
    ]
  };

  final LinkProvider _link;

  AddMomentEvent(String path, this._link) : super(path);

  @override
  void onInvoke(Map<String, dynamic> params) {
    var name = params[_name] as String;
    var sched = getSchedule();
    if (sched.schedule.events.contains((Event e) => e.name == name)) {
      throw new ArgumentError.value(name, _name, 'An event by that name already exists');
    }

    var val = parseInputValue(params[_value]);
    var spec = params[_isSpecial] ?? false;
    var pri = params[_priority] ?? 0;
    var dates = params[_date] as String;
    String dateStr;
    if (dates.contains(r'/')) {
      dateStr = dates.split(r'/')[0];
    } else {
      dateStr = dates;
    }

    var date = DateTime.parse(dateStr);

    var tr = new TimeRange.moment(date);
    var evnt = new Event(name, tr, val, isSpecial: spec, priority: pri);
    sched.addEvent(evnt);

    var en = provider.addNode('${parent.path}/${evnt.id}', EventsNode.def(evnt)) as EventsNode;
    if (en != null) {
      en.event = evnt;
    }
    _link.save();
  }
}

class AddRecurringEvents extends ScheduleChild {
  static const String isType = 'addRecurringEvents';
  static const String pathName = 'add_recurring_events';

  static Map<String, dynamic> def() => {
    r'$name': 'Add Recurring Event',
    r'$is': isType,
    r'$params': [
      {
        'name': _name,
        'type': 'string',
        'placeholder': 'Activate Light',
        'description': 'Identifiable name for the event.'
      },
      {
        'name': _value,
        'type': 'dynamic',
        'description': 'Value when event is triggered'
      },
      {
        'name': _dateRange,
        'type': 'string',
        'editor': 'daterange',
        'description': 'Start and end date range of the event.'
      },
      {
        'name': _timeRange,
        'type': 'string',
        'editor': 'daterange',
        'description': 'Start and end times of the event. Only the time the event is "active"'
      },
      {
        'name': _freq,
        'type': 'enum[Single,Hourly,Daily,Weekly,Monthly,Yearly]',
        'default': 'Single',
        'description': 'Frequency the event occurs.'
      },
      {
        'name': _isSpecial,
        'type': 'bool',
        'default': 'false',
        'description': 'Flag indicating if this is considered a special event'
      },
      {
        'name': _priority,
        'type': 'number',
        'editor': 'int',
        'min': 0,
        'max': 9,
        'default': 0,
        'description': 'Event priority. 0 is none specified; 1 is highest; 9 is lowest.'
      }
    ],
    r'$invokable': 'write'
  };

  static const String _name = 'name';
  static const String _dateRange = 'dateRange';
  static const String _timeRange = 'timeRange';
  static const String _freq = 'frequency';
  static const String _priority = 'priority';
  static const String _isSpecial = 'isSpecial';
  static const String _value = 'value';

  final LinkProvider _link;
  AddRecurringEvents(String path, this._link): super(path);

  @override
  void onInvoke(Map<String, dynamic> params) {
    var name = params[_name] as String;
    var sched = getSchedule();
    if (sched.schedule.events.contains((Event e) => e.name == name)) {
      throw new ArgumentError.value(name, _name, 'An event by that name already exists');
    }
    
    String dates = params[_dateRange] as String;
    String times = params[_timeRange] as String;

    if (!dates.contains(r'/')) {
      throw new ArgumentError.value(dates, _dateRange,
          'Unexpected date range. Should be in the format <startDate>/<endDate>');
    }
    if (!times.contains(r'/')) {
      throw new ArgumentError.value(times, _timeRange,
          'Unexpected time range. Should be in the format <startTime>/<endTime>');
    }

    var dateRange = (params[_dateRange] as String).split(r'/');
    var timeRange = (params[_timeRange] as String).split(r'/');
    var sDate = DateTime.parse(dateRange[0]).toLocal();
    var eDate = DateTime.parse(dateRange[1]).toLocal();
    var sTime = DateTime.parse(timeRange[0]).toLocal();
    var eTime = DateTime.parse(timeRange[1]).toLocal();

    var fStr = params[_freq] as String;
    var freq = FrequencyFromString(fStr.toLowerCase());
    if (freq == null) {
      throw new ArgumentError.value(fStr, _freq, 'Invalid frequency');
    }

    var duration = eTime.difference(sTime);

    var startDate = new DateTime(sDate.year, sDate.month, sDate.day,
        sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
    var endDate = eDate;
    var startTime = startDate;
    var endTime = startTime.add(duration);
    var tr = new TimeRange(startTime, endTime, startDate, endDate, freq);

    var val = parseInputValue(params[_value]);
    var spec = params[_isSpecial] ?? false;
    var pri = params[_priority] ?? 0;
    
    var evnt = new Event(name, tr, val, isSpecial: spec, priority: pri);
    sched.addEvent(evnt);

    var en = provider.addNode('${parent.path}/${evnt.id}', EventsNode.def(evnt)) as EventsNode;
    if (en != null) {
      en.event = evnt;
    }

    _link.save();
  }
}

class EventsNode extends ScheduleChild {
  static const String isType = 'eventsNode';

  static const String _id = 'id';
  static const String _name = 'name';
  static const String _priority = 'priority';
  static const String _isSpecial = 'isSpecial';
  static const String _val = 'value';
  static const String _sTime = 'startTime';
  static const String _eTime = 'endTime';
  static const String _dur = 'duration';
  static const String _sDate = 'startDate';
  static const String _eDate = 'endDate';
  static const String _freq = 'frequency';

  static Map<String, dynamic> def(Event e) {
    var map = <String,dynamic>{
      r'$is': isType,
      r'$name': e.name,
      _id: {r'$name': 'ID', r'$type': 'string', r'?value': e.id},
      RemoveAction.pathName: RemoveAction.def()
    };

    if (e.timeRange.period > new Duration(seconds: 1)) {
      map[_dur] = {
        r'$name': 'Duration',
        r'$type': 'number',
        r'?value': e.timeRange.period.inSeconds,
        r'@unit': 'seconds'
      };
    }

    return map;
  }

  Event _event;
  Completer<Event> _comp;
  void set event(Event e) {
    _event = e;
    if (!_comp.isCompleted) _comp.complete(e);
  }

  Future<Event> getEvent() async {
    if (_event != null) return _event;
    return _comp.future;
  }

  EventsNode(String path) : super(path) {
    _comp = new Completer<Event>();
    serializable = false;
  }

  @override
  void onCreated() {
    getEvent().then(_populateNodes);
  }

  void _populateNodes(Event e) {
    _addEditableDate(_sTime, 'Start Time', e.timeRange.sTime, (DateTime date) {
      _updateTimeRange(e, sTime: date);
      _updateSchedule(_event);
      _updateDuration();
    });
    _addEditableDate(_sDate, 'Start Date', e.timeRange.sDate, (DateTime date) {
      _updateTimeRange(e, sDate: date);
      _updateSchedule(_event);
    });
    _addEditableDate(_eTime, 'End Time', e.timeRange.eTime, (DateTime date) {
      _updateTimeRange(e, eTime: date);
      _updateSchedule(_event);
      _updateDuration();
    });
    _addEditableDate(_eDate, 'End Date', e.timeRange.eDate, (DateTime date) {
      _updateTimeRange(e, eDate: date);
      _updateSchedule(_event);
    });

    provider.addNode('$path/$_freq', EventFrequency.def(e.timeRange.frequency));
    provider.addNode('$path/$_val', EventValue.def(e.value));
    provider.addNode('$path/$_isSpecial', EventIsSpecial.def(e.isSpecial));
    provider.addNode('$path/$_priority', EventPriority.def(e.priority));
    provider.addNode('$path/${EditEvent.pathName}', EditEvent.def(e));
  }

  @override
  void onRemoving() {
    var sched = getSchedule();
    if (sched == null) return;

    sched.removeEvent(name);
  }

  bool updateFrequency(String freq) {
    var f = FrequencyFromString(freq.toLowerCase());
    if (f == null) return true; // True to reject value.

    getEvent().then((Event e) {
      _updateTimeRange(e, freq: f);
      _updateSchedule(e);
    });
    return false;
  }

  bool updateEventVal(Object value) {
    var sched = getSchedule();
    sched.updateEventVal(name, value);
    return false;
  }

  bool updateSpecial(bool isSpecial) {
    getEvent().then((Event e) {
      e.isSpecial = isSpecial;
      _updateSchedule(e);
    });

    return false;
  }

  /// Sets the event priority to that specified. Removes and re-adds the event
  /// to the schedule to ensure appropriate event priorities are managed
  bool updatePriority(int priority) {
    getEvent().then((Event e) {
      e.priority = priority;
      _updateSchedule(e);
    });

    return false;
  }

  void editEvent(Event e) {
    _updateSchedule(e);
    displayName = e.name;
    _updateValues(_priority, e.priority);
    _updateValues(_isSpecial, e.isSpecial);
    _updateValues(_val, e.value);
    _updateValues(_sTime, e.timeRange.sTime.toIso8601String());
    _updateValues(_eTime, e.timeRange.eTime.toIso8601String());
    _updateValues(_sDate, e.timeRange.sDate.toIso8601String());
    _updateValues(_eDate, e.timeRange.eDate.toIso8601String());
    var freq = e.timeRange.frequency.toString().split(r'.')[1];
    _updateValues(_freq, freq);
    if (e.timeRange.period > new Duration(seconds: 1)) {
      _updateValues(_dur, e.timeRange.period.inSeconds);
    }

    RemoveNode(provider, children[EditEvent.pathName]);
    provider.addNode('$path/${EditEvent.pathName}', EditEvent.def(e));
  }

  void _updateValues(String node, Object value) {
    (children[node] as SimpleNode).updateValue(value);
  }

  void _updateTimeRange(Event e, {DateTime sTime, DateTime sDate, DateTime eTime,
    DateTime eDate, Frequency freq}) {
    DateTime st = sTime ?? e.timeRange.sTime;
    DateTime sd = sDate ?? e.timeRange.sDate;
    DateTime et = eTime ?? e.timeRange.eTime;
    DateTime ed = eDate ?? e.timeRange.eDate;
    Frequency f = freq ?? e.timeRange.frequency;

    var tr = new TimeRange(st, et, sd, ed, f);
    e.updateTimeRange(tr);
  }

  /// Remove and re-add the event to the schedule, forcing the schedule to be
  /// recalculated.
  void _updateSchedule(Event e) {
    // Remove and re-add event if we've updated it, as this may change it's
    // next timestamp or even priority.
    var sched = getSchedule();
    sched.replaceEvent(e);
  }

  void _updateDuration() {
    var durNode = provider.getNode('$path/$_dur');
    if (durNode == null) return;
    durNode.updateValue(_event.timeRange.period.inSeconds);
  }

  void _addEditableDate(String path, String name, DateTime value, OnEditDate onEdit) {
    var node = provider.addNode('${this.path}/$path',
        EventDateTime.def(name, value.toIso8601String())) as EventDateTime;
    node.onEdit = onEdit;
  }
}

class EditEvent extends ScheduleChild {
  static const String isType = 'schedule/event/edit';
  static const String pathName = 'edit_event';

  static const String _name = 'name';
  static const String _dateRange = 'dateRange';
  static const String _timeRange = 'timeRange';
  static const String _freq = 'frequency';
  static const String _priority = 'priority';
  static const String _isSpecial = 'isSpecial';
  static const String _value = 'value';

  static Map<String, dynamic> def(Event e) {
    var sdate = e.timeRange.sDate.toIso8601String();
    var edate = e.timeRange.eDate.toIso8601String();
    var stime = e.timeRange.sTime.toIso8601String();
    var etime = e.timeRange.eTime.toIso8601String();

    var freq = e.timeRange.frequency.toString().split('.')[1];

    return <String,dynamic>{
      r'$name': 'Edit Event',
      r'$is': isType,
      r'$params': [
        {
          'name': _name,
          'type': 'string',
          'default': e.name,
          'description': 'Identifiable name for the event.'
        },
        {
          'name': _value,
          'type': 'dynamic',
          'default': e.value,
          'description': 'Value when event is triggered'
        },
        {
          'name': _dateRange,
          'type': 'string',
          'editor': 'daterange',
          'default': '$sdate/$edate',
          'description': 'Start and end date range of the event.'
        },
        {
          'name': _timeRange,
          'type': 'string',
          'editor': 'daterange',
          'default': '$stime/$etime',
          'description': 'Start and end times of the event. Only the time the event is "active"'
        },
        {
          'name': _freq,
          'type': 'enum[Single,Hourly,Daily,Weekly,Monthly,Yearly]',
          'default': freq,
          'description': 'Frequency the event occurs.'
        },
        {
          'name': _isSpecial,
          'type': 'bool',
          'default': e.isSpecial,
          'description': 'Flag indicating if this is considered a special event'
        },
        {
          'name': _priority,
          'type': 'number',
          'editor': 'int',
          'min': 0,
          'max': 9,
          'default': e.priority,
          'description': 'Event priority. 0 is none specified; 1 is highest; 9 is lowest.'
        }
      ],
      r'$invokable': 'write'
    };
  }

  final LinkProvider _link;
  EditEvent(String path, this._link) : super(path) {
    serializable = false;
  }

  @override
  Future onInvoke(Map<String, dynamic> params) async {
    var schedNode = getSchedule();
    var existing = await (parent as EventsNode).getEvent();
    var name = _checkName(params[_name], existing, schedNode.schedule);

    var dates = _checkDates(params[_dateRange]);
    var times = _checkDates(params[_timeRange]);
    var freq = _checkFreq(params[_freq]);
    var val = parseInputValue(params[_value]);
    var spec = params[_isSpecial];
    var pri = params[_priority];

    // Get event window duration
    var dur = times[1].difference(times[0]);
    var startDate = new DateTime(dates[0].year, dates[0].month, dates[0].day,
        times[0].hour, times[0].minute, times[0].second, times[0].millisecond);
    var endDate = new DateTime(dates[1].year, dates[1].month, dates[1].day,
        times[1].hour, times[1].minute, times[1].second, times[1].millisecond);
    var startTime = startDate;
    var endTime = startTime.add(dur);
    var tr = new TimeRange(startTime, endTime, startDate, endDate, freq);
    var evnt = new Event(name, tr, val, isSpecial: spec, priority: pri, id: existing.id);

    (parent as EventsNode).editEvent(evnt);
    _link.save();
  }

  String _checkName(String name, Event existing, Schedule sched) {
    if (name == existing.name) return name;

    if (name == null || name.trim().isEmpty) {
      throw new ArgumentError.value(name, _name, 'value cannot be empty.');
    }

    if (sched.events.any((Event e) => e.name == name && e.id != existing.id)) {
      throw new ArgumentError.value(name, _name, 'an event by that name already exists');
    }

    return name;
  }

  List<DateTime> _checkDates(String dates) {
    List<DateTime> res = new List<DateTime>(2);

    if (!dates.contains(r'/')) {
      throw new ArgumentError.value(dates, _dateRange,
          'Unexpected date range. Should be in the format <startDate>/<endDate>');
    }

    var ds = dates.split(r'/');
    res[0] = DateTime.parse(ds[0]).toLocal();
    res[1] = DateTime.parse(ds[1]).toLocal();
    return res;
  }

  Frequency _checkFreq(String freq) {
    var f = FrequencyFromString(freq.toLowerCase());
    if (f == null) {
      throw new ArgumentError.value(freq, _freq, 'invalid frequency interval');
    }

    return f;
  }
}

typedef void OnEditDate(DateTime date);

class EventDateTime extends SimpleNode {
  static const String isType = 'eventDateTime';

  static Map<String, dynamic> def(String name, String value) => {
    r'$is': isType,
    r'$name': name,
    r'$writable': 'write',
    r'$type': 'string',
    r'?value': value
  };

  OnEditDate onEdit;

  EventDateTime(String path) : super(path) {
    serializable = false;
  }

  @override
  bool onSetValue(Object value) {
    // Reject a non-string value for datetime.
    if (value is! String) return true;

    var date = DateTime.parse(value);
    onEdit(date);
    return false;
  }
}

class EventFrequency extends SimpleNode {
  static const String isType = 'schedule/event/frequency';

  static Map<String, dynamic> def(Frequency freq) {
    var freqStr = Frequency
        .values
        .map((Frequency f) => f.toString().split(r'.')[1])
        .join(',');
    var freqVal = freq.toString().split(r'.')[1];

    var m = {
      r'$is': isType,
      r'$name': 'Frequency',
      r'$type': 'enum[$freqStr]', r'?value': freqVal,
      r'$writable': 'write'
    };
    return m;
  }

  EventFrequency(String path): super(path) {
    serializable = false;
  }

  @override
  bool onSetValue(Object value) {
    if (value is! String) return true;

    return (parent as EventsNode).updateFrequency(value);
  }
}

class EventValue extends SimpleNode {
  static const String isType = 'schedule/event/value';

  static Map<String, dynamic> def(dynamic value) => {
    r'$is': isType,
    r'$name': 'Value',
    r'$type': 'dynamic',
    r'?value': value,
    r'$writable': 'write'
  };

  EventValue(String path) : super(path) {
    serializable = false;
  }

  @override
  bool onSetValue(Object value) {
    return (parent as EventsNode).updateEventVal(value);
  }
}

class EventIsSpecial extends SimpleNode {
  static const String isType = 'schedule/event/isSpecial';

  static Map<String, dynamic> def(bool special) => {
    r'$is': isType,
    r'$name': 'Special',
    r'$type': 'bool',
    r'?value': special,
    r'$writable': 'write'
  };

  EventIsSpecial(String path) : super(path) {
    serializable = false;
  }

  @override
  bool onSetValue(Object value) {
    bool spec;
    if (value is bool) {
      spec = value;
    } else if (value is String) {
      spec = (value.toLowerCase().trim() == 'true');
    } else {
      return true;
    }

    return (parent as EventsNode).updateSpecial(spec);
  }
}

class EventPriority extends SimpleNode {
  static const String isType = 'schedule/event/priority';

  static Map<String, dynamic> def(int priority) => {
    r'$is': isType,
    r'$name': 'Priority',
    r'$type': 'number',
    r'$editor': 'int',
    r'$min': '0',
    r'$max': '9',
    r'?value': priority,
    r'$writable': 'write'
  };

  EventPriority(String path) : super(path) {
    serializable = false;
  }

  @override
  bool onSetValue(Object value) {
    num number;
    if (value is num) {
      number = value;
    } else if (value is String) {
      number = num.parse(value);
    } else {
      return true;
    }

    return (parent as EventsNode).updatePriority(number);
  }
}