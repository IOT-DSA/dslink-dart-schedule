
/// Zero length duration handy for difference calculations.
const zeroDur = const Duration();

/// Represents the frequency an event may happen. It can be a `Single` event, or
/// occur `Daily`, `Weekly`, `Monthly`, or `Yearly`
enum Frequency {Single, Hourly, Daily, Weekly, Monthly, Yearly}

/// A TimeRange is the period of time over which an [Event] occurs. A TimeRange
/// may be a single moment, a simple range, or a TimeRange that occurs at a
/// specific [Frequency]
class TimeRange {
  /// Start time of the TimeRange.
  DateTime sTime;
  /// End Time of the TimeRange.
  DateTime eTime;
  /// Start date of the TimeRange.
  DateTime sDate;
  /// End date of the TimeRange. This should be the last day on which the event
  /// occurs. (If an event spans multiple days it should be the last day of the
  /// event ending, not the last day the event starts on).
  DateTime eDate;
  /// How often the event should repeat over the DateRange
  Frequency frequency;
  /// Returns the duration of the event window (EndTime - StartTime)
  Duration get period => eTime.difference(sTime);
  /// Returns the duration of the full TimeRange (EndDate - StartDate)
  Duration get duration => eDate.difference(sDate);
  /// Returns the endPoint of the TimeRange no events should occur past this
  DateTime get _end => new DateTime(eDate.year, eDate.month, eDate.day,
          eTime.hour, eTime.minute, eTime.second, eTime.millisecond);

  final RangeError _freq =
      new RangeError('Start and End Times exceed the specified Frequency');

  /// Creates a new TimeRange that spans the same time (from sTime to eTime)
  /// by default on a daily basis between sDate and eDate (inclusive). Otherwise
  /// frequency may be one of the Frequency enumerated values.
  /// sTime and eTime should be the start and end times of the _first_ window
  /// of the TimeRange. For instance if this TimeRange represents a period of
  /// time from 11:00am - 12:00pm (one hour) between July 1st - July 15th 2020
  /// ```var range = TimeRange(new DateTime(
  TimeRange(this.sTime, this.eTime, this.sDate, this.eDate,
      [this.frequency = Frequency.Daily]) {

    if (_end.isAfter(eDate)) {
      throw new RangeError('End Date must be after the end of the period for that day.');
    }

    switch (frequency) {
      case Frequency.Hourly:
        if (period > new Duration(hours: 1)) throw _freq;
        break;
      case Frequency.Daily:
        if (period > new Duration(days: 1)) throw _freq;
        break;
      case Frequency.Monthly:
        if (period > new Duration(days: 30)) throw _freq;
        break;
      case Frequency.Yearly:
        if (period > new Duration(days: 365)) throw _freq;
        break;
      default: break;
    }
  }

  /// This constructor takes a single moment in time for the TimeRange.
  factory TimeRange.moment(DateTime dateTime) =>
      new TimeRange(dateTime, dateTime, dateTime, dateTime, Frequency.Single);

  /// A single Time Range, with a start and end period that is inclusive.
  factory TimeRange.single(DateTime start, DateTime end) =>
      new TimeRange(start, end, start, end, Frequency.Single);

  /// Returns true if this TimeRange contains the _day_ [day]
  /// (does not validate time). Note that Weekly and Monthly
  /// events may encompass the same period but _not_ take place
  /// on the same day. For example if a TimeRange is Weekly starting on a
  /// Thursday and [TimeRange] is a month, any DateTime that is not on a
  /// Thursday will return false.
  bool sameDay(DateTime day) {
    // Reset day so it's midnight of that day. Helps prevent issues where
    // it's the same day, but "day" is later than the time of endDate.
    day = new DateTime(day.year, day.month, day.day);
    var windowDur = period;

    // Check if it's the same as start day
    if (sameDayOfYear(sDate, day)) return true;
    // Check if it's the same as the end day
    if (frequency == Frequency.Single || frequency == Frequency.Daily) {
      if (sameDayOfYear(eDate, day)) return true;
    }

    // if negative duration then day is prior to the start day.
    var diff = day.difference(sDate);
    if (diff < zeroDur) return false;

    // if greater that means day is after the end date.
    diff = day.difference(eDate);
    if (diff > zeroDur) return false;

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

  bool includes(DateTime moment) {
    // Before the start or after the end, it's not included.
    if (moment.isBefore(sTime) || moment.isAfter(_end)) return false;

    // In between the start end end of the first day (if applicable)
    if ((moment.isAtSameMomentAs(sTime) || moment.isAfter(sTime))
        && (moment.isAtSameMomentAs(eTime) || moment.isBefore(eTime))) {
      return true;
    }

    switch (frequency) {
      case Frequency.Hourly:
        return _hourlyInclude(moment);
      case Frequency.Daily:
        return _dailyInclude(moment);
      default: return false;
    }
  }

  bool _hourlyInclude(DateTime moment) {
    var hourStart = new DateTime(moment.year, moment.month, moment.day,
        moment.hour, sTime.minute, sTime.second, sTime.millisecond);
    var hourEnd = hourStart.add(period);

    return (moment.isAfter(hourStart) || moment.isAtSameMomentAs(hourStart))
        && (moment.isBefore(hourEnd) || moment.isAtSameMomentAs(hourEnd));
  }

  bool _dailyInclude(DateTime moment) {
    var dayStart = new DateTime(moment.year, moment.month, moment.day,
        sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
    var dayEnd = dayStart.add(period);

    return (moment.isAfter(dayStart) || moment.isAtSameMomentAs(dayStart))
        && (moment.isBefore(dayEnd) || moment.isAtSameMomentAs(dayEnd));
  }
}

bool sameDayOfYear(DateTime d1, DateTime d2) {
  return d1.day == d2.day && d1.month == d2.month && d1.year == d2.year;
}