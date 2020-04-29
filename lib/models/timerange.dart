
/// Zero length duration handy for difference calculations.
const zeroDur = const Duration();

/// Represents the frequency an event may happen. It can be a `Single` event, or
/// occur `Daily`, `Weekly`, `Monthly`, or `Yearly`
enum Frequency {Single, Hourly, Daily, Weekly, Monthly, Yearly}

/// Returns a [Frequency] based on the string input. Returns null if no match.
Frequency FrequencyFromString(String freq) {
  switch (freq) {
    case 'single': return Frequency.Single;
    case 'hourly': return Frequency.Hourly;
    case 'daily': return Frequency.Daily;
    case 'weekly': return Frequency.Weekly;
    case 'monthly': return Frequency.Monthly;
    case 'yearly': return Frequency.Yearly;
    default: return null;
  }
}

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

  final RangeError _freqErr =
      new RangeError('Start and End Times exceed the specified Frequency');

  static const String _sTime = 'sTime';
  static const String _eTime = 'eTime';
  static const String _sDate = 'sDate';
  static const String _eDate = 'eDate';
  static const String _freq = 'freq';

  DateTime _nextTs;

  /// Creates a new TimeRange that spans the same time (from sTime to eTime)
  /// by default on a daily basis between sDate and eDate (inclusive). Otherwise
  /// frequency may be one of the Frequency enumerated values.
  /// sTime and eTime should be the start and end times of the _first_ window
  /// of the TimeRange. For instance if this TimeRange represents a period of
  /// time from 11:00am - 12:00pm (one hour) between July 1st - July 15th 2020
  /// ```var range = TimeRange(new DateTime(
  TimeRange(this.sTime, this.eTime, this.sDate, this.eDate,
      [this.frequency = Frequency.Daily]) {

    if (!sameDayOfYear(sTime, sDate)) {
      throw new StateError('Start Time and Start Date do not match');
    }

    if (_end.isAfter(eDate)) {
      throw new RangeError('End Date must be after the end of the period for that day.');
    }

    if (sTime.isAfter(eTime)) {
      throw new StateError('Start time must be before End time');
    }

    if (sDate.isAfter(eDate)) {
      throw new StateError('Start date must be before End date');
    }

    switch (frequency) {
      case Frequency.Hourly:
        if (period > new Duration(hours: 1)) throw _freqErr;
        break;
      case Frequency.Daily:
        if (period > new Duration(days: 1)) throw _freqErr;
        break;
      case Frequency.Monthly:
        if (period > new Duration(days: 30)) throw _freqErr;
        break;
      case Frequency.Yearly:
        if (period > new Duration(days: 365)) throw _freqErr;
        break;
      default: break;
    }
  }

  /// Create a new [TimeRange] object from an existing json map.
  factory TimeRange.fromJson(Map<String, dynamic> map) {
    var sTime = DateTime.parse(map[_sTime]);
    var eTime = DateTime.parse(map[_eTime]);
    var sDate = DateTime.parse(map[_sDate]);
    var eDate = DateTime.parse(map[_eDate]);
    var freq = Frequency.values[map[_freq]];

    return new TimeRange(sTime, eTime, sDate, eDate, freq);
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
  bool sameDay(DateTime date) {
    // Reset day so it's midnight of that day. Helps prevent issues where
    // it's the same day, but "day" is later than the time of endDate.
    var day = new DateTime(date.year, date.month, date.day);
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

  /// This method returns `true` if [moment] takes place during one of this
  /// TimeRange's windows. If the specified [moment] is within the TimeRange's
  /// Start and End dates but is not within the active window, this method will
  /// return `false`.
  bool includes(DateTime moment) {
    // Before the start or after the end, it's not included.
    if (moment.isBefore(sTime) || moment.isAfter(eDate)) return false;

    // In between the start end end of the first day (if applicable)
    if (inRange(moment, sTime, eTime)) return true;

    DateTime start;
    DateTime end;

    switch (frequency) {
      case Frequency.Hourly:
        start = new DateTime(moment.year, moment.month, moment.day,
            moment.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Daily:
        start = new DateTime(moment.year, moment.month, moment.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Weekly:
        var offSet = moment.weekday - sDate.weekday;
        // Dart lets us use a negative day and will properly roll-back to the
        // previous month without manually handling the changes. So it's okay if
        // day - offSet is a negative number.
        start = new DateTime(moment.year, moment.month, moment.day - offSet,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Monthly:
        start = new DateTime(moment.year, moment.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Yearly:
        start = new DateTime(moment.year, sTime.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      default: return false;
    }
    end = start.add(period);

    return inRange(moment, start, end);
  }

  /// Returns the [DateTime] of the next instance of this event starting on or
  /// after [moment]. If moment is null, the current time will be used. This
  /// method will only return the starting time of the next event, but it will
  /// not return any events already in progress. If there are no instances of
  /// the event after [moment], this method will return null.
  DateTime nextTs([DateTime moment]) {
    // If moment is null assume we're looking for events after "now"
    var isNow = (moment == null);
    // Remove 100ms from current time to help account for timer being off
    // by a few ms.
    if (isNow) {
      moment = new DateTime.now().subtract(const Duration(milliseconds: 100));
    }

    if (_nextTs != null && _nextTs.isAfter(moment)) return _nextTs;

    // It's before the first event so send first event
    if (moment.isBefore(sTime) || moment.isAtSameMomentAs(sTime)) return sTime;

    if (!inRange(moment, sTime, eDate)) {
      return null;
    }

    DateTime next;

    switch (frequency) {
      case Frequency.Single:
        return null; // Handled in the first check
      case Frequency.Hourly:
        next = new DateTime(moment.year, moment.month, moment.day,
            moment.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Daily:
        next = new DateTime(moment.year, moment.month, moment.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Weekly:
        var offSet = moment.weekday - sDate.weekday;
        next = new DateTime(moment.year, moment.month, moment.day - offSet,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Monthly:
        next = new DateTime(moment.year, moment.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Yearly:
        next = new DateTime(moment.year, sTime.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
    }

    // Double check that the current matching hour would still be in range
    if (!inRange(next, sTime, eDate)) return null;
    // Check if moment prior to the start the next period of the same timeframe
    if (moment.isBefore(next) || moment.isAtSameMomentAs(next)) {
      // if we're using current time, cache the next result
      if (isNow) _nextTs = next;

      return next;
    }

    // It's not at the same frequency so check next frequency:

    switch (frequency) {
      case Frequency.Single:
        return null; // Handled in the first check
      case Frequency.Hourly:
        next = new DateTime(next.year, next.month, next.day,
            next.hour + 1, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Daily:
        next = new DateTime(next.year, next.month, next.day + 1,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Weekly:
        next = new DateTime(next.year, next.month, next.day + 7,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Monthly:
        next = new DateTime(next.year, next.month + 1, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Yearly:
        next = new DateTime(next.year + 1, sTime.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
    }

    if (includes(next)) {
      if (isNow) _nextTs = next;
      return next;
    }
    return null;
  }

  /// Returns a [Duration] of the time remaining in this TimeRange's currently
  /// running period. If the TimeRange is not currently have, this method
  /// returns `null`.
  Duration remaining([DateTime moment]) {
    moment ??= new DateTime.now();

    if (!includes(moment)) return null;

    // In between the start end end of the first day (if applicable)
    if (moment.isAfter(sTime) && moment.isBefore(eTime)) {
      return eTime.difference(moment);
    }

    DateTime start;
    DateTime end;

    switch (frequency) {
      case Frequency.Single:
        return null;
      case Frequency.Hourly:
        start = new DateTime(moment.year, moment.month, moment.day,
            moment.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Daily:
        start = new DateTime(moment.year, moment.month, moment.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Weekly:
        var offSet = moment.weekday - sDate.weekday;
        // Dart lets us use a negative day and will properly roll-back to the
        // previous month without manually handling the changes. So it's okay if
        // day - offSet is a negative number.
        start = new DateTime(moment.year, moment.month, moment.day - offSet,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Monthly:
        start = new DateTime(moment.year, moment.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      case Frequency.Yearly:
        start = new DateTime(moment.year, sTime.month, sTime.day,
            sTime.hour, sTime.minute, sTime.second, sTime.millisecond);
        break;
      default: return null;
    }
    end = start.add(period);

    if (inRange(moment, start, end)) return end.difference(moment);

    return null;
  }

/// Export TimeRange configuration to a json map.
  Map<String, dynamic> toJson() => {
    _sTime: sTime.toIso8601String(),
    _eTime: eTime.toIso8601String(),
    _sDate: sDate.toIso8601String(),
    _eDate: eDate.toIso8601String(),
    _freq: frequency.index
  };
}

/// Check if the D1 and D2 occur on the same day. Return `true` if so, and false
/// if not. If d1, d2 or both are null, it also returns false (as they are not dates)
bool sameDayOfYear(DateTime d1, DateTime d2) {
  if (d1 == null || d2 == null) return false;
  return d1.day == d2.day && d1.month == d2.month && d1.year == d2.year;
}

/// Returns `true` if [start] <= moment <= [end]. Returns false if moment is
/// before start or after end.
bool inRange(DateTime moment, DateTime start, DateTime end) {
  return (moment.isAfter(start) || moment.isAtSameMomentAs(start)) &&
      (moment.isBefore(end) || moment.isAtSameMomentAs(end));
}
