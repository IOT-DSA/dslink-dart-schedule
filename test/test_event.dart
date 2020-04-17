import 'package:test/test.dart';

import 'package:dslink_schedule/models/event.dart';
import 'package:dslink_schedule/models/timerange.dart';

void main() {
  test('Constructor', event_constructor);
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