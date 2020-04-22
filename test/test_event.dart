import 'package:test/test.dart';

import 'package:dslink_schedule/models/event.dart';
import 'package:dslink_schedule/models/timerange.dart';

void main() {
  test('Constructor', event_constructor);
  test('toJson', event_toJson);
  test('fromJson', event_fromJson);
  test('getPriority', test_getPriority);
}

void event_constructor() {
  var testId = 'A' * 50;
  var val = 42;
  var tr = new TimeRange.moment(new DateTime(2020, 4, 12, 6, 45));

  var e = new Event("test", tr, val);
  expect(e.name, equals("test"));
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isFalse);
  expect(e.priority, equals(0));
  expect(e.id, isNotNull);
  expect(e.id.length, equals(50));

  e = new Event("test", tr, val, isSpecial: true);
  expect(e.name, equals("test"));
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isTrue);
  expect(e.priority, equals(0));
  expect(e.id, isNotNull);
  expect(e.id.length, equals(50));

  e = new Event("test", tr, val, priority: 9);
  expect(e.name, equals("test"));
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isFalse);
  expect(e.priority, equals(9));
  expect(e.id, isNotNull);
  expect(e.id.length, equals(50));

  e = new Event("test", tr, val, id: testId);
  expect(e.name, equals("test"));
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isFalse);
  expect(e.priority, equals(0));
  expect(e.id, equals(testId));

  e = new Event("test", tr, val, isSpecial: true, priority: 1, id: testId);
  expect(e.name, equals("test"));
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isTrue);
  expect(e.priority, equals(1));
  expect(e.id, equals(testId));
}

void event_toJson() {
  var testId = 'A' * 50;
  var val = 42;
  var tr = new TimeRange.moment(new DateTime(2020, 4, 12, 6, 45));
  var e = new Event("test", tr, val, isSpecial: true, priority: 1, id: testId);
  var res = {
    'name': 'test',
    'id': testId,
    'priority': 1,
    'special': true,
    'value': 42,
    'timeRange': {
      'sTime': '2020-04-12T06:45:00.000',
      'eTime': '2020-04-12T06:45:00.000',
      'sDate': '2020-04-12T06:45:00.000',
      'eDate': '2020-04-12T06:45:00.000',
      'freq': 0
    }
  };

  expect(e.toJson(), equals(res));
}

void event_fromJson() {
  var testId = 'A' * 50;
  var date = new DateTime(2020, 4, 12, 6, 45);
  var res = {
    'name': 'test',
    'id': testId,
    'priority': 1,
    'special': true,
    'value': 42,
    'timeRange': {
      'sTime': '2020-04-12T06:45:00.000',
      'eTime': '2020-04-12T06:45:00.000',
      'sDate': '2020-04-12T06:45:00.000',
      'eDate': '2020-04-12T06:45:00.000',
      'freq': 0
    }
  };

  var e = new Event.fromJson(res);
  expect(e.name, equals('test'));
  expect(e.id, equals(testId));
  expect(e.priority, equals(1));
  expect(e.isSpecial, isTrue);
  expect(e.value, equals(42));
  expect(e.timeRange.sTime, equals(date));
  expect(e.timeRange.eTime, equals(date));
  expect(e.timeRange.sDate, equals(date));
  expect(e.timeRange.eDate, equals(date));
  expect(e.timeRange.frequency, equals(Frequency.Single));
}

void test_getPriority() {
  var tr = new TimeRange.moment(new DateTime.now());
  var a = new Event('A', tr, 'a');
  var b = new Event('B', tr, 'b');

  // Both same, expect A.
  expect(getPriority(a, b).id, equals(a.id));
  b.isSpecial = true;
  // B special expect B.
  expect(getPriority(a, b).id, equals(b.id));
  a.priority = 1;
  // A is higher priority but B is special. Expect B
  expect(getPriority(a, b).id, equals(b.id));

  a.isSpecial = true;
  // A is higher priority, both special. Expect B.
  expect(getPriority(a, b).id, equals(a.id));

  a.priority = 4;
  b.priority = 3;
  // B is higher priority, expect B.
  expect(getPriority(a, b).id, equals(b.id));

  a = null;
  expect(getPriority(a, b).id, equals(b.id));
  expect(getPriority(b, a).id, equals(b.id));

  expect(getPriority(null, null), equals(null));
}