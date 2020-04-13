import 'dart:async';

/// Represents the frequency an event may happen. It can be a `Single` event, or
/// occur `Daily`, `Weekly`, `Monthly`, or `Yearly`
enum Frequency {Single, Hourly, Daily, Weekly, Monthly, Yearly}

/// Zero length duration handy for difference calculations.
const zeroDur = const Duration();

/// A schedule contains a default value (may be null) and a list of 0 or more
/// events that occur during that schedule.
class Schedule {
  /// The schedule will provide this Event when no event is active.
  Event defaultValue;
  /// List of events that make up the schedule.
  List<Event> events;
  /// The event that is currently active.
  Event current;
  /// Next event scheduled to be active.
  Event next;
  /// Stream of values from the schedule which are generated at the appropriate
  /// time.
  Stream<Object> get values => _controller.stream;

  Timer _timer;
  StreamController<Object> _controller;

// Should schedules provide the values with a stream? Stream of values
// Broadcast stream, since that won't block when not listened.
}

class Event {
  /// Priority level 0 - 9. 0 Is no priority specified. 1 is highest 9 is lowest.
  /// An event will only start
  int priority = 0;
  /// specialEvent indicates if this event should supersede all other events
  /// for that day. Not to be confused with a higher priority, which will allow
  /// the other events to still occur as long as they do not over-lap.
  bool isSpecial = false;
  /// Value to be set when event is active
  Object value;
  /// The Date and Time range, and frequency over that period, the event should
  /// occur.
  TimeRange timeRange;
}

class TimeRange {
  /// Start time of the TimeRange.
  DateTime sTime;
  /// End Time of the TimeRange.
  DateTime eTime;
  /// Start date of the TimeRange.
  DateTime sDate;
  /// End date of the TimeRange.
  DateTime eDate;
  /// How often the event should repeat over the DateRange
  Frequency frequency;

  /// Creates a new TimeRange that spans the same time (from sTime to eTime)
  /// by default on a daily basis between sDate and eDate (inclusive). Otherwise
  /// frequency may be one of the Frequency enumerated values.
  TimeRange(this.sTime, this.eTime, this.sDate, this.eDate,
      [this.frequency = Frequency.Daily]);

  /// This constructor takes a single moment in time for the TimeRange.
  factory TimeRange.Moment(DateTime dateTime) =>
      new TimeRange(dateTime, dateTime, dateTime, dateTime, Frequency.Single);

  /// A single Time Range, with a start and end period that is inclusive.
  factory TimeRange.Single(DateTime start, DateTime end) =>
      new TimeRange(start, end, start, end, Frequency.Single);

  /// Returns true if this TimeRange contains the _day_ [day]
  /// (does not validate time). Note that Weekly and Monthly
  /// events may encompass the same period but _not_ take place
  /// on the same day. For example if a TimeRange is Weekly starting on a
  /// Thursday and [TimeRange] is a month, any DateTime that is not on a
  /// Thursday will return false.
  bool sameDay(DateTime day) {
    // TODO: Test the hell out of this one
    var diff = day.difference(sDate);
    // if negative duration then day is prior to the start day.
    if (diff < zeroDur) return false;

    diff = day.difference(eDate);
    // if greater that means day is after the end date.
    if (diff > zeroDur) return false;

    var windowDur = eTime.difference(sTime);

    switch (frequency) {
      case Frequency.Single:
      case Frequency.Hourly:
      case Frequency.Daily: return true;
      case Frequency.Weekly: return day.weekday == sDate.weekday;
      case Frequency.Monthly:
      // Already know we're inside of the start and end dates
      // So check the day of month
        if (day.day == sTime.day) return true;
        // If its a big window, check if we're inside that window for this month
        if (windowDur.inDays > 0) {
          var tmpStart = new DateTime(sTime.year, day.month, sTime.day, sTime.hour, sTime.minute, sTime.second);
          var tmpEnd = tmpStart.add(windowDur);
          return (day.isAtSameMomentAs(tmpStart) || day.isAfter(tmpStart)) &&
              (day.isAtSameMomentAs(tmpEnd) || day.isBefore(tmpEnd));
        }
        return false;
      case Frequency.Yearly:
      // Already know we're inside the start and end dates.
      // So check day and month
        if (day.day == sTime.day && day.month == sTime.month) return true;
        // If it's a big window, check if its in that window, for this year.
        if (windowDur.inDays > 0) {
          var tmpStart = new DateTime(day.year, sTime.month, sTime.day, sTime.hour, sTime.minute, sTime.second);
          var tmpEnd = tmpStart.add(windowDur);
          return (day.isAtSameMomentAs(tmpStart) || day.isAfter(tmpStart)) &&
              (day.isAtSameMomentAs(tmpEnd) || day.isBefore(tmpEnd));
        }
        return false;
    } // End switch

    // Default, assume no. Should never hit here?
    return false;
  }
}