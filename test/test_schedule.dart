import 'dart:async';
import 'package:test/test.dart';

import 'package:dslink_schedule/models/schedule.dart';
import 'package:dslink_schedule/models/event.dart';
import 'package:dslink_schedule/models/timerange.dart';

void main() {
  test('Schedule.Constructor', schedule_constructor);
  test('Schedule.Add', schedule_add);
  test('Schedule.GetTsIndex', test_getTsIndex);
}

Future<Null> schedule_constructor() async {
  var sched = new Schedule('Test', true);
  expect(sched.name, equals('Test'));
  expect(sched.defaultValue, isTrue);
  expect(sched.events, isEmpty);
  expect(sched.currentValue, sched.defaultValue);
  
  var sc = await sched.values.first;
  expect(sc, sched.defaultValue);
}

void schedule_add() {
  var now = new DateTime.now();
  var start = now.add(new Duration(seconds: 5));
  var end = start.add(new Duration(seconds: 10));
  var sched = new Schedule('Test', true);

  var tr = new TimeRange.single(start, end);

  var event = new Event('Test Event', tr, 42);

  sched.add(event);

  expect(sched.events.length, equals(1));
}

void test_getTsIndex() {
  var now = new DateTime.now();
  var list = [
    new Event('Test1', new TimeRange.moment(new DateTime(2019, 12, 25)), 25),
    new Event('Test2', new TimeRange.moment(new DateTime(2020, 1, 1)), 1),
    // Expect to insert here, ind = 2
    new Event('Test3', new TimeRange.moment(now.add(new Duration(days: 2))), 20),
    new Event('Test4', new TimeRange.moment(now.add(new Duration(days: 5))), 5)
  ];

  var date = now.add(new Duration(days: 1));
  expect(getTsIndex(list, date), equals(2));
}