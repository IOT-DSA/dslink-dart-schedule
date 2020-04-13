import 'package:dslink_schedule/models/schedule.dart';

import 'package:test/test.dart';

void main() {
  test("TimeRange.Constructors", timeRange_constructors);
  test("TimeRange.SameDay", timeRange_sameDay);
}

void timeRange_constructors() {
  // Moment Constructor - April 12th @ 6:45am
  var moment = new DateTime(2020, 4, 12, 6, 45);
  var tr = new TimeRange.Moment(moment);
  expect(tr.frequency, equals(Frequency.Single));
  expect(moment.isAtSameMomentAs(tr.sTime), isTrue);
  expect(moment.isAtSameMomentAs(tr.eTime), isTrue);
  expect(moment.isAtSameMomentAs(tr.sDate), isTrue);
  expect(moment.isAtSameMomentAs(tr.eDate), isTrue);
  // Redundant but why not.
  expect(tr.sTime.isAtSameMomentAs(tr.sDate), isTrue);
  expect(tr.eTime.isAtSameMomentAs(tr.eDate), isTrue);
  // More Redundant but not true in next batch
  expect(tr.sTime.isAtSameMomentAs(tr.eTime), isTrue);
  expect(tr.sDate.isAtSameMomentAs(tr.eDate), isTrue);

  // Single (range) Constructor April 12 @ 6:45am - April 12 @ 6:45pm
  var start = new DateTime(2020, 4, 12, 6, 45);
  var end = new DateTime(2020, 4, 12, 18, 45); // 12 hour period.
  tr = new TimeRange.Single(start, end);
  expect(tr.frequency, equals(Frequency.Single));
  expect(start.isAtSameMomentAs(tr.sTime), isTrue);
  expect(end.isAtSameMomentAs(tr.eTime), isTrue);
  expect(start.isAtSameMomentAs(tr.sDate), isTrue);
  expect(end.isAtSameMomentAs(tr.eDate), isTrue);
  expect(tr.sTime.isAtSameMomentAs(tr.sDate), isTrue);
  expect(tr.eTime.isAtSameMomentAs(tr.eDate), isTrue);
  // Should not match
  expect(tr.sTime.isAtSameMomentAs(tr.eTime), isFalse);
  expect(tr.sDate.isAtSameMomentAs(tr.eDate), isFalse);

  // Single (range) Constructor April 12 @ 12:00pm - April 15 @ 12:00pm
  start = new DateTime(2020, 4, 12, 12, 0);
  end = new DateTime(2020, 4, 15, 12, 0); // 3 day period.
  tr = new TimeRange.Single(start, end);
  expect(tr.frequency, equals(Frequency.Single));
  expect(start.isAtSameMomentAs(tr.sTime), isTrue);
  expect(end.isAtSameMomentAs(tr.eTime), isTrue);
  expect(start.isAtSameMomentAs(tr.sDate), isTrue);
  expect(end.isAtSameMomentAs(tr.eDate), isTrue);
  expect(tr.sTime.isAtSameMomentAs(tr.sDate), isTrue);
  expect(tr.eTime.isAtSameMomentAs(tr.eDate), isTrue);
  // Should not match
  expect(tr.sTime.isAtSameMomentAs(tr.eTime), isFalse);
  expect(tr.sDate.isAtSameMomentAs(tr.eDate), isFalse);

  // Range Constructor default April 12 - April 18, 9:00am - 12:00pm daily.
  var startTime = new DateTime(2020, 4, 12, 9);
  var endTime = new DateTime(2020, 4, 12, 12);
  var startDate = new DateTime(2020, 4, 12);
  var endDate = new DateTime(2020, 4, 18);
  tr = new TimeRange(startTime, endTime, startDate, endDate);
  expect(tr.frequency, equals(Frequency.Daily));
  expect(startTime.isAtSameMomentAs(tr.sTime), isTrue);
  expect(endTime.isAtSameMomentAs(tr.eTime), isTrue);
  expect(startDate.isAtSameMomentAs(tr.sDate), isTrue);
  expect(endDate.isAtSameMomentAs(tr.eDate), isTrue);
  // Should not match
  expect(tr.sTime.isAtSameMomentAs(tr.sDate), isFalse);
  expect(tr.eTime.isAtSameMomentAs(tr.eDate), isFalse);
  expect(tr.sTime.isAtSameMomentAs(tr.eTime), isFalse);
  expect(tr.sDate.isAtSameMomentAs(tr.eDate), isFalse);
}

void timeRange_sameDay() {
  // Moment Constructor - April 12th @ 6:45am
  var moment = new DateTime(2020, 4, 12, 6, 45);
  var tr = new TimeRange.Moment(moment);
  expect(tr.sameDay(moment), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight next day
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier

  // Single (range) Constructor April 12 @ 6:45am - April 12 @ 6:45pm
  var start = new DateTime(2020, 4, 12, 6, 45);
  var end = new DateTime(2020, 4, 12, 18, 45); // 12 hour period.
  tr = new TimeRange.Single(start, end);
  expect(tr.sameDay(moment), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight next day
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
}