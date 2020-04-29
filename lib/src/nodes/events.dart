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
    var spec = params[_isSpecial];
    var pri = params[_priority];
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
    var spec = params[_isSpecial];
    var pri = params[_priority];
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
    var spec = params[_isSpecial];
    var pri = params[_priority];
    
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
    var freqStr = Frequency
        .values
        .map((Frequency f) => f.toString().split(r'.')[1])
        .join(',');
    var freqVal = e.timeRange.frequency.toString().split(r'.')[1];
    var map = <String,dynamic>{
      r'$is': isType,
      r'$name': e.name,
      _id: {r'$name': 'ID', r'$type': 'string', r'?value': e.id},
      _val: {r'$name': 'Value', r'$type': 'dynamic', r'?value': e.value},
      _sTime: {r'$name': 'Start time', r'$type': 'string', r'?value': e.timeRange.sTime.toIso8601String()},
      _sDate: {r'$name': 'Start Date', r'$type': 'string', r'?value': e.timeRange.sDate.toIso8601String()},
      _eDate: {r'$name': 'End Date', r'$type': 'string', r'?value': e.timeRange.eDate.toIso8601String()},
      _freq: {r'$name': 'Frequency', r'$type': 'enum[$freqStr]', r'?value': freqVal},
      _isSpecial: {r'$name': 'Special', r'$type': 'bool', r'?value': e.isSpecial},
      _priority: {r'$name': 'Priority', r'$type': 'number', r'?value': e.priority},
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

  Event event;

  EventsNode(String path) : super(path) {
    serializable = false;
  }

  @override
  void onRemoving() {
    var sched = getSchedule();
    if (sched == null) return;

    sched.removeEvent(name);
  }
}