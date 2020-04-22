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

  var tr1 = new TimeRange.single(start, end);
  var event1 = new Event('Test Event', tr1, 42);

  var tr2 = new TimeRange.moment(end);
  var event2 = new Event('Test Two', tr2, 50);

  start = now.add(new Duration(days: 1));
  end = start.add(new Duration(minutes: 10));
  var tr3 = new TimeRange.single(start, end);
  var event3 = new Event('Test three', tr3, 100);

  // Add backwards but check they are added in the correct order.
  sched.add(event2);
  sched.add(event3);
  sched.add(event1);

  expect(sched.events.length, equals(3));
  expect(sched.events[0].id, equals(event1.id));
  expect(sched.events[1].id, equals(event2.id));
  expect(sched.events[2].id, equals(event3.id));
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