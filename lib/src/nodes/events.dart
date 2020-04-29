import 'package:dslink/dslink.dart';

import 'package:dslink/utils.dart' show logger;
import 'package:dslink/nodes.dart' show NodeNamer;

import 'package:dslink_schedule/schedule.dart';
import 'package:dslink_schedule/utils.dart' show parseInputValue;
import 'package:dslink_schedule/models/timerange.dart';

import 'schedule.dart';

class AddEventsNode extends SimpleNode {
  static const String isType = 'addEventsNode';
  static const String pathName = 'add_events';

  static Map<String, dynamic> def() => {
    r'$name': 'Add Event',
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
  AddEventsNode(String path, this._link): super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    var name = params[_name] as String;
    
    var encName = NodeNamer.createName(name);
    var nd = provider.getNode('${parent.path}/$encName');
    if (nd != null) {
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

    var sch = getSchedule();
    sch.addEvent(evnt);

    provider.addNode('${parent.path}/${evnt.id}', EventsNode.def(evnt));

    _link.save();
  }

  ScheduleNode getSchedule() {
    var schedPath = parent.parent.path;
    var sched = provider.getNode(schedPath) as ScheduleNode;
    if (sched == null) {
      logger.warning('Unable to remove event, could not find schedule');
      return null;
    }

    return sched;
  }
}

class EventsNode extends SimpleNode {
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
      'remove': { r'$is': 'remove', r'$name': 'Remove', r'$invokable': 'write'}
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
    // construct the nodes each time no need to serialize
    serializable = false;
  }

  @override
  void onRemoving() {
    var sched = getSchedule();
    if (sched == null) return;

    String id;
    if (event != null) {
      id = event.id;
    } else {
      var idNode = children[_id] as SimpleNode;
      id = idNode.value;
    }

    if (id != null) {
      sched.removeEvent(id);
    }
  }

  ScheduleNode getSchedule() {
    var sched = parent as ScheduleNode;
    if (sched == null) {
      logger.warning('Unable to remove event, could not find schedule');
      return null;
    }

    return sched;
  }
}