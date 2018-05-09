import 'dart:async';

import 'package:dslink/dslink.dart';
import 'package:timezone/src/location.dart';
import 'package:dslink_schedule/calendar.dart';
import "package:dslink_schedule/ical.dart" as ical;

abstract class ICalendarLocalSchedule extends SimpleNode {
  List<Map> get specialEvents;
  List<Map> get weeklyEvents;
  String get generatedCalendar;
  ical.CalendarObject get rootCalendarObject;

  Location timezone;
  ValueCalendarState get state;
  Future loadSchedule([bool isUpdate = false]);
  String calculateTag();

  Future<Null> addStoredEvent(ical.StoredEvent event);
  Future updateStoredEvent(String eventId, Map eventData);
  void removeStoredEvent(String name);

  ICalendarLocalSchedule(String path) : super(path);
}
