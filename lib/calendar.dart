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

  ValueAtTime getCurrent() {
    return provider.current();
  }

  List<FunctionDisposable> _listeners = [];

  int lid = 0;

  FunctionDisposable listen(func(ValueAtTime v)) {
    Timer timer;
    Timer timer2;

    var id = lid++;
    var isFirst = true;

    check() {
      var current = getCurrent();
      if (current == null) {
        return;
      }

      Duration nextCheck;

      if (current.isHappeningNow) {
        if (!current.deliveredTo.contains(id)) {
          if (timer2 != null) {
            timer2.cancel();
          }
          current.deliveredTo.add(id);
          func(current);
          timer2 = new Timer(current.duration, () {
            if (defaultValue != null) {
              func(defaultValue);
            }
          });
        }
        nextCheck = current.endsIn;
      } else {
        if (isFirst && defaultValue != null) {
          func(defaultValue);
        }
        nextCheck = current.time.difference(new DateTime.now());
      }

      if (const bool.fromEnvironment("debug.next.check", defaultValue: false)) {
        print("[${current.description.name}] Next Check in ${nextCheck.inSeconds} seconds");
      }

      timer = new Timer(nextCheck, () {
        if (!current.deliveredTo.contains(id)) {
          if (timer2 != null) {
            timer2.cancel();
          }
          current.deliveredTo.add(id);
          func(current);
          timer2 = new Timer(current.duration, () {
            if (defaultValue != null) {
              func(defaultValue);
            }
          });
        }
        check();
      });

      isFirst = false;
    }

    check();

    var disposable = new FunctionDisposable(() {
      if (timer != null) {
        timer.cancel();
      }

      if (timer2 != null) {
        timer2.cancel();
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

  List<int> deliveredTo = [];

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
    return time.isBefore(now) && endsAt.isAfter(now);
  }

  @override
  String toString() => "ValueAtTime(${time}, ${value})";
}

class EventDescription {
  final String name;

  dynamic value;
  Duration duration;

  EventDescription(this.name, this.value);
}
