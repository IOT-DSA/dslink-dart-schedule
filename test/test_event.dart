import 'package:test/test.dart';

import 'package:dslink_schedule/models/event.dart';
import 'package:dslink_schedule/models/timerange.dart';

void main() {
  test('Constructor', event_constructor);
}

void event_constructor() {
  var val = 42;
  var tr = new TimeRange.moment(new DateTime(2020, 4, 12, 6, 45));
  var e = new Event(tr, val);
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isFalse);
  expect(e.priority, equals(0));

  e = new Event(tr, val, isSpecial: true);
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isTrue);
  expect(e.priority, equals(0));

  e = new Event(tr, val, priority: 9);
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isFalse);
  expect(e.priority, equals(9));

  e = new Event(tr, val, isSpecial: true, priority: 1);
  expect(e.value, equals(42));
  expect(e.timeRange, equals(tr));
  expect(e.isSpecial, isTrue);
  expect(e.priority, equals(1));
}