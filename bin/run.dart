import 'package:dslink/dslink.dart';
import 'dart:async';
import 'package:dslink_schedule/schedule_link.dart';

dynamic main(List<String> args) async {
  final link = new ScheduleDSLink.withDefaultParams();

  await link.start();
}
