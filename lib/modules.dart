import 'package:dslink_schedule/services.dart';
import 'package:dslink_schedule/nodes.dart';
import 'package:di/di.dart';

Module get diModule => new Module()
  ..bind(CalendarFetcher);
