library dslink.schedule.calendar;

import "dart:async";

import "package:dslink/utils.dart";

abstract class CalendarProvider {
  ValueAtTime next(ValueCalendarState state);
  ValueAtTime current();
  List<EventDescription> listEvents();
}

class ValueCalendarState {
  final CalendarProvider provider;

  ValueCalendarState(this.provider);

  ValueAtTime defaultValue;

  ValueAtTime getNext() {
    return provider.next(this);
  }

  List<ValueAtTime> _queue = [];

  ValueAtTime getCurrent() {
    if (_queue.isNotEmpty) {
      return _queue.first;
    }
    var m = provider.current();
    _queue.add(m);
    return m;
  }

  List<FunctionDisposable> _listeners = [];

  int lid = 0;

  FunctionDisposable listen(func(ValueAtTime v)) {
    Timer timer;

    var isFirst = true;

    check() {
      if (timer != null && timer.isActive) {
        timer.cancel();
      }

      var current = getCurrent();

      if (current == null) {
        if (defaultValue != null) {
          logger.fine("[${current.description.name}] Back to Default (Current is null.)");
          func(defaultValue);
        }
        return;
      }

      logger.fine("Current Event: ${current}");

      if (current.isHappeningNow) {
        logger.fine("[${current.description.name}] Happening Now: ${current}");
        if (!current.delivered) {
          logger.fine(
              "[${current.description.name}] Delivering Value ${current}");
          func(current);
          current.delivered = true;
        }
      } else if (current.hasAlreadyHappened) {
        if (defaultValue != null) {
          logger.fine("[${current.description.name}] Back to Default (Current has already happened.)");
          func(defaultValue);
          _queue.remove(current);
        }
      } else {
        var now = new DateTime.now();
        if ((now.isAfter(current.endsAt) || now.isAtSameMomentAs(current.endsAt)) && defaultValue != null) {
          logger.fine("[${current.description.name}] Back to Default (Gap)");
          func(defaultValue);
          _queue.remove(current);
        } else if (isFirst && defaultValue != null) {
          logger.fine("[${current.description.name}] Back to Default (First)");
          func(defaultValue);
          _queue.remove(current);
        }
      }

      timer = new Timer(const Duration(seconds: 1), () {
        check();
      });

      isFirst = false;
    }

    check();

    var disposable = new FunctionDisposable(() {
      if (timer != null) {
        timer.cancel();
      }
    });

    _listeners.add(disposable);

    return disposable;
  }

  void dispose() {
    _listeners.forEach((x) => x.dispose());
    _listeners.clear();
  }
}

class ValueAtTime {
  final DateTime time;
  final dynamic value;
  final Duration duration;
  final EventDescription description;
  final bool isDefault;

  ValueAtTime(this.time, this.value, this.duration, this.description, [this.isDefault = false]);

  factory ValueAtTime.forDefault(val) {
    return new ValueAtTime(
        new DateTime.fromMillisecondsSinceEpoch(0),
        val,
        const Duration(days: 36500000),
        new EventDescription("Default", val),
        true
    );
  }

  DateTime _ended;

  bool delivered = false;

  DateTime get endsAt {
    if (_ended == null) {
      _ended = time.add(duration);
    }
    return _ended;
  }

  Duration get until => time.difference(new DateTime.now());

  Duration get endsIn {
    return endsAt.difference(new DateTime.now());
  }

  bool get hasAlreadyHappened {
    var now = new DateTime.now();
    return endsAt.isBefore(now) || endsAt.isAtSameMomentAs(now) || endsAt.difference(now).inSeconds == 0;
  }

  bool get isHappeningNow {
    var now = new DateTime.now();
    var conditionA = time.isBefore(now) || time.isAtSameMomentAs(now);
    var conditionB = endsAt.isAfter(now) || endsAt.isAtSameMomentAs(now);
    return conditionA && conditionB;
  }

  @override
  String toString() => "ValueAtTime(at ${time} delivers ${value} for ${duration.inSeconds} seconds)";
}

class EventDescription {
  final String name;

  dynamic value;
  Duration duration;

  EventDescription(this.name, this.value);
}
