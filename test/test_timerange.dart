import 'package:test/test.dart';

import 'package:dslink_schedule/models/timerange.dart';

final DaylightSavings = new DateTime(2020, 3, 8, 2);

void main() {
  test("TimeRange.Moment Constructor", timeRange_moment_constructor);
  test("TimeRange.Single Constructor", timeRnage_single_constructor);
  test("TimeRange Constructor", timeRange_constructor);
  test("TimeRange throws error", timeRange_constructor_error);
  test("TimeRange.SameDay", timeRange_sameDay);
  test("TimeRange.Includes", timeRange_includes);
  test("TimeRange.Moment.nextAfter", timeRange_moment_nextAfter);
  test("TimeRange.Single.nextAfter", timeRange_single_nextAfter);
  test("TimeRange.Hourly.nextAfter", timeRange_hourly_nextAfter);
  test("TimeRange.Daily.nextAfter", timeRange_daily_nextAfter);
  test("TimeRange.Weekly.nextAfter", timeRange_weekly_nextAfter);
  test("TimeRange.Monthly.nextAfter", timeRange_monthly_nextAfter);
  test("TimeRange.Yearly.nextAfter", timeRange_yearly_nextAfter);
}

void timeRange_moment_constructor() {
  // Moment Constructor - April 12th @ 6:45am
  var moment = new DateTime(2020, 4, 12, 6, 45);
  var tr = new TimeRange.moment(moment);
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
}

void timeRnage_single_constructor() {
  // Single (range) Constructor April 12 @ 6:45am - April 12 @ 6:45pm
  var start = new DateTime(2020, 4, 12, 6, 45);
  var end = new DateTime(2020, 4, 12, 18, 45); // 12 hour period.
  var tr = new TimeRange.single(start, end);
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
  tr = new TimeRange.single(start, end);
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
}

void timeRange_constructor() {
  // Range Constructor default April 12 - April 18, 9:00am - 12:00pm daily.
  var startTime = new DateTime(2020, 4, 12, 9);
  var endTime = new DateTime(2020, 4, 12, 12);
  var startDate = new DateTime(2020, 4, 12);
  var endDate = new DateTime(2020, 4, 18, 12);
  var tr = new TimeRange(startTime, endTime, startDate, endDate);
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

  // Range Constructor default April 12 - April 18, 11:30pm - 12:30am Daily.
  startTime = new DateTime(2020, 4, 12, 23, 30);
  endTime = new DateTime(2020, 4, 13, 0, 30);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 18, 0, 30);
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

  // Range Constructor April 12 - April 18, 9:00am - 9:30am, Hourly.
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 9, 30);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 18, 9, 30);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly);
  expect(tr.frequency, equals(Frequency.Hourly));
  expect(startTime.isAtSameMomentAs(tr.sTime), isTrue);
  expect(endTime.isAtSameMomentAs(tr.eTime), isTrue);
  expect(startDate.isAtSameMomentAs(tr.sDate), isTrue);
  expect(endDate.isAtSameMomentAs(tr.eDate), isTrue);
  // Should not match
  expect(tr.sTime.isAtSameMomentAs(tr.sDate), isFalse);
  expect(tr.eTime.isAtSameMomentAs(tr.eDate), isFalse);
  expect(tr.sTime.isAtSameMomentAs(tr.eTime), isFalse);
  expect(tr.sDate.isAtSameMomentAs(tr.eDate), isFalse);

  // Range Constructor April 12 - May 12, 9:00am - 12:00pm Weekly.
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 12);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 18, 12);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Weekly);
  expect(tr.frequency, equals(Frequency.Weekly));
  expect(startTime.isAtSameMomentAs(tr.sTime), isTrue);
  expect(endTime.isAtSameMomentAs(tr.eTime), isTrue);
  expect(startDate.isAtSameMomentAs(tr.sDate), isTrue);
  expect(endDate.isAtSameMomentAs(tr.eDate), isTrue);
  // Should not match
  expect(tr.sTime.isAtSameMomentAs(tr.sDate), isFalse);
  expect(tr.eTime.isAtSameMomentAs(tr.eDate), isFalse);
  expect(tr.sTime.isAtSameMomentAs(tr.eTime), isFalse);
  expect(tr.sDate.isAtSameMomentAs(tr.eDate), isFalse);

  // Range Constructor April 12, 2020 - April 12, 2021. 9:00am - 12:00pm Monthly
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 12);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2021, 4, 12, 12);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Weekly);
  expect(tr.frequency, equals(Frequency.Weekly));
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

void timeRange_constructor_error() {
  // Check for failing constructors
  // These should throw a RangeError

  // Range Constructor April 12 - April 13. 9am - 12pm, Hourly
  var startTime = new DateTime(2020, 4, 12, 9);
  var endTime = new DateTime(2020, 4, 12, 12);
  var startDate = new DateTime(2020, 4, 12);
  var endDate = new DateTime(2020, 4, 13);
  expect(() =>
  new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly),
      throwsRangeError);

  // Range Constructor April 12 - April 18. 9am - 9:30am following day, Daily
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 13, 9, 30);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 18);
  expect(() =>
  new TimeRange(startTime, endTime, startDate, endDate, Frequency.Daily),
      throwsRangeError);

  // Range Constructor April 12 2020 - April 12 2021. 9am - 9:30am following day, Monthly
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 5, 12, 9, 30);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2021, 4, 12);
  expect(() =>
  new TimeRange(startTime, endTime, startDate, endDate, Frequency.Monthly),
      throwsRangeError);

  // Range Constructor April 12 2020 - April 12 2030. Full year & 1 second, Yearly
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2021, 4, 12, 9, 0, 1);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2030, 4, 12);
  expect(() =>
  new TimeRange(startTime, endTime, startDate, endDate, Frequency.Yearly),
      throwsRangeError);

  // Range Constructor April 12 9am - 9:15am Hourly
  // End Date shouldn't be before endTime
  startTime = new DateTime(2020, 4, 12, 9);
  endTime =   new DateTime(2020, 4, 12, 9, 15);
  startDate = new DateTime(2020, 4, 12);
  endDate =   new DateTime(2020, 4, 12);
  expect(() =>
  new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly),
      throwsRangeError);

  // State Errors
  // Start Time and Date do not match days
  startTime = new DateTime(2020, 4, 12, 9);
  endTime =   new DateTime(2020, 4, 12, 9, 15);
  startDate = new DateTime(2020, 4, 13);
  endDate =   new DateTime(2020, 4, 13, 9, 15);
  expect(() =>
  new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly),
      throwsStateError);
}

void timeRange_sameDay() {
  // Moment Constructor - April 12th @ 6:45am
  var moment = new DateTime(2020, 4, 12, 6, 45);
  var tr = new TimeRange.moment(moment);
  expect(tr.sameDay(moment), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight next day
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 4, 12)), isFalse); // 20 years later

  // Single (range) Constructor April 12 @ 6:45am - April 12 @ 6:45pm
  var start = new DateTime(2020, 4, 12, 6, 45);
  var end = new DateTime(2020, 4, 12, 18, 45); // 12 hour period.
  tr = new TimeRange.single(start, end);
  expect(tr.sameDay(start), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 4, 12)), isFalse); // 20 years later

  // Single (range) Constructor April 12 @ 6:45pm - April 13 @ 6:45am
  start = new DateTime(2020, 4, 12, 18, 45);
  end = new DateTime(2020, 4, 13, 6, 45); // 12 hour period.
  tr = new TimeRange.single(start, end);
  expect(tr.sameDay(start), isTrue);
  expect(tr.sameDay(end), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isTrue); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 13, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 14)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 4, 12)), isFalse); // 20 years later

  // Range Constructor default April 12 - April 18, 9:00am - 12:00pm daily.
  var startTime = new DateTime(2020, 4, 12, 9);
  var endTime = new DateTime(2020, 4, 12, 12);
  var startDate = new DateTime(2020, 4, 12);
  var endDate = new DateTime(2020, 4, 18, 12);
  tr = new TimeRange(startTime, endTime, startDate, endDate);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isTrue); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 18)), isTrue); // Midnight of last day
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 18, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 14)), isTrue); // Midweek
  expect(tr.sameDay(new DateTime(2020, 4, 19)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 4, 12)), isFalse); // 20 years later

  // Range Constructor default April 12 - April 18, 11:30pm - 12:30am Daily.
  startTime = new DateTime(2020, 4, 12, 23, 30);
  endTime = new DateTime(2020, 4, 13, 0, 30);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 19, 0, 30);
  tr = new TimeRange(startTime, endTime, startDate, endDate);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isTrue); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 18)), isTrue); // Midnight of last day
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 19, 23, 59)), isTrue); // Just prior to midnight of last day
  expect(tr.sameDay(new DateTime(2020, 4, 20, 23, 59)), isFalse); // Just prior to midnight of following day
  expect(tr.sameDay(new DateTime(2020, 4, 14)), isTrue); // Midweek
  expect(tr.sameDay(new DateTime(2020, 4, 19)), isTrue); // Next day
  expect(tr.sameDay(new DateTime(2020, 4, 20)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 4, 12)), isFalse); // 20 years later

  // Range Constructor default April 12 - April 13, 9:00am - 9:15pm Hourly.
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 9, 15);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 13, 9, 15);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isTrue); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 13, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 4, 14)), isFalse); // Next day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 4, 12)), isFalse); // 20 years later

  // Range Constructor default Sunday April 12 - Tuesday May 12, 9:00am - 10:00pm Weekly.
  // Only same day of the week in this range should match (eg Sundays)
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 10);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 5, 12, 10);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Weekly);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isFalse); // It's not the same day of the week
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isFalse); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 12, 23, 59)), isFalse); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 10)), isTrue); // Sunday May 10 is a sunday
  expect(tr.sameDay(new DateTime(2020, 5, 10, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 13)), isFalse); // Next Day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 5, 12)), isFalse); // 20 years later

  // Range Constructor Sunday April 12 2020 - Tuesday April 12 2021,
  // 9:00am - 10:00pm Monthly.
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 10);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2021, 4, 12, 10);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Monthly);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isFalse); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2021, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 12)), isTrue); // Next Month
  expect(tr.sameDay(new DateTime(2020, 12, 12)), isTrue); // Later in the year
  expect(tr.sameDay(new DateTime(2021, 4, 12)), isTrue); // Next Year
  expect(tr.sameDay(new DateTime(2021, 4, 13)), isFalse); // Next Year
  expect(tr.sameDay(new DateTime(2021, 5, 12)), isFalse); // Next Year
  expect(tr.sameDay(new DateTime(2020, 5, 10)), isFalse); // Sunday May 10 is a sunday
  expect(tr.sameDay(new DateTime(2020, 5, 13)), isFalse); // Next Day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 5, 12)), isFalse); // 20 years later

  // Range Constructor Sunday April 12 2020 - Tuesday April 12 2021,
  // 1 week duration (so we need to see if we overlap any of the days) monthly
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 18, 9);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2021, 4, 12, 9);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Monthly);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isTrue); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 18)), isTrue); // Midnight last day
  expect(tr.sameDay(new DateTime(2020, 4, 19)), isFalse); // Midnight next day
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2021, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 7, 15, 23, 59)), isTrue); // Mid-july in range
  expect(tr.sameDay(new DateTime(2020, 5, 12)), isTrue); // Next Month
  expect(tr.sameDay(new DateTime(2020, 7, 18)), isTrue); // Later in the year
  expect(tr.sameDay(new DateTime(2020, 12, 15)), isTrue); // Later in the year
  expect(tr.sameDay(new DateTime(2020, 7, 30)), isFalse); // Later in the year
  expect(tr.sameDay(new DateTime(2021, 4, 12)), isTrue); // Next Year
  expect(tr.sameDay(new DateTime(2021, 4, 13)), isFalse); // Next Year
  expect(tr.sameDay(new DateTime(2021, 5, 12)), isFalse); // Next Year
  expect(tr.sameDay(new DateTime(2020, 5, 10)), isFalse); // Sunday May 10 is a sunday
  expect(tr.sameDay(new DateTime(2021, 4, 13)), isFalse); // Next Day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2040, 5, 12)), isFalse); // 20 years later

  // Range Sunday April 12 2020 - Friday April 12 2030,
  // 1 week duration (so we need to see if we overlap any of the days). Yearly
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 18, 9);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2030, 4, 12, 9);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Yearly);
  expect(tr.sameDay(startDate), isTrue);
  expect(tr.sameDay(endDate), isTrue);
  expect(tr.sameDay(new DateTime(2020, 4, 12)), isTrue); // Midnight day of
  expect(tr.sameDay(new DateTime(2020, 4, 13)), isTrue); // Midnight day after
  expect(tr.sameDay(new DateTime(2020, 4, 18)), isTrue); // Midnight last day
  expect(tr.sameDay(new DateTime(2020, 4, 19)), isFalse); // Midnight next day
  expect(tr.sameDay(new DateTime(2020, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 5, 12, 23, 59)), isFalse); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2021, 4, 12, 23, 59)), isTrue); // Just prior to midnight
  expect(tr.sameDay(new DateTime(2020, 7, 15, 23, 59)), isFalse); // Mid-july in range
  expect(tr.sameDay(new DateTime(2020, 5, 12)), isFalse); // Next Month
  expect(tr.sameDay(new DateTime(2020, 7, 18)), isFalse); // Later in the year
  expect(tr.sameDay(new DateTime(2020, 12, 15)), isFalse); // Later in the year
  expect(tr.sameDay(new DateTime(2020, 7, 30)), isFalse); // Later in the year
  expect(tr.sameDay(new DateTime(2021, 4, 12)), isTrue); // Next Year
  expect(tr.sameDay(new DateTime(2021, 4, 13)), isTrue); // Next Year
  expect(tr.sameDay(new DateTime(2025, 4, 15)), isTrue); // In 5 Years
  expect(tr.sameDay(new DateTime(2021, 5, 12)), isFalse); // Next Year
  expect(tr.sameDay(new DateTime(2020, 5, 10)), isFalse); // Sunday May 10 is a sunday
  expect(tr.sameDay(new DateTime(2030, 4, 13)), isFalse); // Next Day
  expect(tr.sameDay(new DateTime(2000, 4, 12)), isFalse); // 20 years earlier
  expect(tr.sameDay(new DateTime(2050, 5, 12)), isFalse); // 20 years later
}

void timeRange_includes() {
  // April 12th @ 9:15am.
  var time = new DateTime(2020, 4, 12, 9, 15);
  var tr = new TimeRange.moment(time);
  expect(tr.includes(time), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 9, 15, 1)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 9, 14, 59)), isFalse);

  // April 12th @ 9am - 12pm
  var start = new DateTime(2020, 4, 12, 9);
  var end = new DateTime(2020, 4, 12, 12);
  tr = new TimeRange.single(start, end);
  expect(tr.includes(start), isTrue);
  expect(tr.includes(end), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 9, 0, 1)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 12, 0, 1)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 8, 59, 59)), isFalse);

  // April 12 @ 9am - 9:15 Hourly.
  var startTime = new DateTime(2020, 4, 12, 9);
  var endTime = new DateTime(2020, 4, 12, 9, 15);
  var startDate = new DateTime(2020, 4, 12);
  var endDate = new DateTime(2020, 4, 12, 21, 15);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly);
  expect(tr.includes(startTime), isTrue);
  expect(tr.includes(endTime), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 11, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 21, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 9, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 12, 35)), isFalse);

  // April 12 - 18 @ 9am - 9pm Daily.
  startTime = new DateTime(2020, 4, 12, 9);
  endTime = new DateTime(2020, 4, 12, 21);
  startDate = new DateTime(2020, 4, 12);
  endDate = new DateTime(2020, 4, 18, 21);
  tr = new TimeRange(startTime, endTime, startDate, endDate);
  expect(tr.includes(startTime), isTrue);
  expect(tr.includes(endTime), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 11, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 20, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 18, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 18, 20, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 18, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 19, 12, 5)), isFalse);

  // April 11 - May 16 (8am Sat - 8pm Sun) - Weekly
  startTime = new DateTime(2020, 4, 11, 8);
  endTime = new DateTime(2020, 4, 12, 20);
  startDate = new DateTime(2020, 4, 11);
  endDate = new DateTime(2020, 5, 16, 20);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Weekly);
  expect(tr.includes(startTime), isTrue);
  expect(tr.includes(endTime), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 10, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 11, 8, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 11, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 11, 23, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 19, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 12, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 18, 22, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 19, 10, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 19, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 2, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 2, 22, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 3, 10, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 3, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 3, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 5, 10, 10)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 5, 12, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 5, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 16, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 16, 10, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 16, 21, 25)), isFalse);

  // April 1 2020 - April 1 2021 Midnight to 11:59:59pm on the first - Monthly
  startTime = new DateTime(2020, 4, 1);
  endTime = new DateTime(2020, 4, 1, 23, 59, 59);
  startDate = new DateTime(2020, 4, 1);
  endDate = new DateTime(2021, 3, 31, 23, 59, 59);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Monthly);
  expect(tr.includes(startTime), isTrue);
  expect(tr.includes(endTime), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 10, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 1, 8, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 1, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 1, 19, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 1, 23, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 2, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 22, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 19, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 1, 8, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 5, 1, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 6, 1, 23, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 7, 1, 9, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 12, 1, 19, 10)), isTrue);
  expect(tr.includes(new DateTime(2021, 3, 1, 19, 10)), isTrue);
  expect(tr.includes(new DateTime(2021, 4, 1, 19, 10)), isFalse);

  // April 1 2020 - April 7 2030 Midnight to 11:59:59pm on the seventh - Yearly
  startTime = new DateTime(2020, 4, 1);
  endTime = new DateTime(2020, 4, 7, 23, 59, 59);
  startDate = new DateTime(2020, 4, 1);
  endDate = new DateTime(2030, 4, 7, 23, 59, 59);
  tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Yearly);
  expect(tr.includes(startTime), isTrue);
  expect(tr.includes(endTime), isTrue);
  expect(tr.includes(new DateTime(2020, 3, 31, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 1, 8, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 2, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 4, 19, 10)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 7, 23, 5)), isTrue);
  expect(tr.includes(new DateTime(2020, 4, 8, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 1, 8, 5)), isFalse);
  expect(tr.includes(new DateTime(2020, 5, 1, 12, 5)), isFalse);
  expect(tr.includes(new DateTime(2021, 3, 31, 9, 5)), isFalse);
  expect(tr.includes(new DateTime(2022, 4, 1, 8, 5)), isTrue);
  expect(tr.includes(new DateTime(2023, 4, 4, 19, 10)), isTrue);
  expect(tr.includes(new DateTime(2025, 4, 2, 12, 5)), isTrue);
  expect(tr.includes(new DateTime(2030, 4, 7, 23, 5)), isTrue);
  expect(tr.includes(new DateTime(2030, 4, 8, 21, 25)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 12, 22)), isFalse);
  expect(tr.includes(new DateTime(2020, 4, 18, 9, 5)), isFalse);
}

void timeRange_moment_nextAfter() {
  var moment = new DateTime(2020, 4, 12, 6, 45);
  var tr = new TimeRange.moment(moment);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(moment));
  expect(tr.nextAfter(new DateTime(2020, 4, 12)), equals(moment));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 6, 45)), equals(moment));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 6, 46)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 4, 13)), equals(null));
}

void timeRange_single_nextAfter() {
  // April 12th 6:45am - 8:45am Single Range.
  var start = new DateTime(2020, 4, 12, 6, 45);
  var end = new DateTime(2020, 4, 12, 8, 45);
  var tr = new TimeRange.single(start, end);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(start));
  expect(tr.nextAfter(new DateTime(2020, 4, 12)), equals(start));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 6, 45)), equals(start));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 6, 46)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 8, 44)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 4, 13)), equals(null));
}

void timeRange_hourly_nextAfter() {
  // April 12th 6:45am - 7:00am Hourly until 9pm.
  var startTime = new DateTime(2020, 4, 12, 6, 45);
  var endTime = new DateTime(2020, 4, 12, 7);
  var startDate = new DateTime(2020, 4, 12);
  var endDate = new DateTime(2020, 4, 12, 21);
  var tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Hourly);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 12)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 6, 45)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 6, 46)), equals(new DateTime(2020, 4, 12, 7, 45)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 8, 44)), equals(new DateTime(2020, 4, 12, 8, 45)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 12)),    equals(new DateTime(2020, 4, 12, 12, 45)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 20)),    equals(new DateTime(2020, 4, 12, 20, 45)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 20, 50)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 21)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 4, 13)), equals(null));
}

void timeRange_daily_nextAfter() {
  // April 1st - May 31st 8am - 5:00pm Daily
  var startTime = new DateTime(2020, 4, 1, 8);
  var endTime = new DateTime(2020, 4, 1, 17);
  var startDate = new DateTime(2020, 4, 1);
  var endDate = new DateTime(2020, 5, 31, 17);
  var tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Daily);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 1, 7, 59)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 12)), equals(new DateTime(2020, 4, 12, 8)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 7, 59)), equals(new DateTime(2020, 4, 12, 8)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 8, 1)), equals(new DateTime(2020, 4, 13, 8)));
  expect(tr.nextAfter(new DateTime(2020, 5, 15, 17, 50)), equals(new DateTime(2020, 5, 16, 8)));
  expect(tr.nextAfter(new DateTime(2020, 5, 31, 17, 50)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 6, 1)), equals(null));
}

void timeRange_weekly_nextAfter() {
  // April 4th - July 5th (9am Saturday - 9pm Sundays) Weekly
  var startTime = new DateTime(2020, 4, 4, 9);
  var endTime = new DateTime(2020, 4, 5, 21);
  var startDate = new DateTime(2020, 4, 4);
  var endDate = new DateTime(2020, 7, 5, 21);
  var tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Weekly);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 4, 8, 59)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 4, 10)), equals(new DateTime(2020, 4, 11, 9)));
  expect(tr.nextAfter(new DateTime(2020, 4, 10)), equals(new DateTime(2020, 4, 11, 9)));
  expect(tr.nextAfter(new DateTime(2020, 4, 12, 8, 1)), equals(new DateTime(2020, 4, 18, 9)));
  expect(tr.nextAfter(new DateTime(2020, 5, 15, 17, 50)), equals(new DateTime(2020, 5, 16, 9)));
  expect(tr.nextAfter(new DateTime(2020, 5, 17, 17, 50)), equals(new DateTime(2020, 5, 23, 9)));
  expect(tr.nextAfter(new DateTime(2020, 7, 4)), equals(new DateTime(2020, 7, 4, 9)));
  expect(tr.nextAfter(new DateTime(2020, 7, 4, 9)), equals(new DateTime(2020, 7, 4, 9)));
  expect(tr.nextAfter(new DateTime(2020, 7, 4, 10)), equals(null));
  expect(tr.nextAfter(new DateTime(2020, 7, 5)), equals(null));
}

void timeRange_monthly_nextAfter() {
  // April 1st - March 31st (First of month, all day)
  var startTime = new DateTime(2020, 4, 1);
  var endTime = new DateTime(2020, 4, 1, 23, 59, 59, 999);
  var startDate = new DateTime(2020, 4, 1);
  var endDate = new DateTime(2021, 3, 31, 23, 59, 59, 999);
  var tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Monthly);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 3, 31, 8, 59)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 4, 10)), equals(new DateTime(2020, 5, 1)));
  expect(tr.nextAfter(new DateTime(2020, 7, 12, 8, 1)), equals(new DateTime(2020, 8, 1)));
  expect(tr.nextAfter(new DateTime(2021, 3, 1)), equals(new DateTime(2021, 3, 1)));
  expect(tr.nextAfter(new DateTime(2021, 3, 1, 0, 0, 1)), equals(null));
  expect(tr.nextAfter(new DateTime(2021, 3, 25)), equals(null));
  expect(tr.nextAfter(new DateTime(2021, 4, 1)), equals(null));
}

void timeRange_yearly_nextAfter() {
  // April 4st 2020 - April 15st 2030 (4th @ 9am - 15th @ 10pm) yearly
  var startTime = new DateTime(2020, 4, 4, 9);
  var endTime =   new DateTime(2020, 4, 15, 22);
  var startDate = new DateTime(2020, 4, 4);
  var endDate =   new DateTime(2030, 4, 15, 22);
  var tr = new TimeRange(startTime, endTime, startDate, endDate, Frequency.Yearly);
  expect(tr.nextAfter(new DateTime(2020, 4, 1)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 4, 8, 59)), equals(startTime));
  expect(tr.nextAfter(new DateTime(2020, 4, 4, 10)), equals(new DateTime(2021, 4, 4, 9)));
  expect(tr.nextAfter(new DateTime(2020, 4, 10, 8, 1)), equals(new DateTime(2021, 4, 4, 9)));
  expect(tr.nextAfter(new DateTime(2021, 3, 1)), equals(new DateTime(2021, 4, 4, 9)));
  expect(tr.nextAfter(new DateTime(2025, 4, 1)), equals(new DateTime(2025, 4, 4, 9)));
  expect(tr.nextAfter(new DateTime(2025, 7, 1)), equals(new DateTime(2026, 4, 4, 9)));
  expect(tr.nextAfter(new DateTime(2030, 3, 1, 0, 0, 1)), equals(new DateTime(2030, 4, 4, 9)));
  expect(tr.nextAfter(new DateTime(2030, 4, 4, 10)), equals(null));
  expect(tr.nextAfter(new DateTime(2030, 6, 1)), equals(null));
}