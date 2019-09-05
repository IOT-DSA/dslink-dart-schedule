library dslink.schedule.main;

import "dart:async";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import 'package:timezone/standalone.dart';

import 'package:dslink_schedule/nodes.dart';
import "package:dslink_schedule/tz.dart";

import 'src/http_server.dart';

LinkProvider link;
//http.Client httpClient = new http.Client();
//SimpleNodeProvider provider;

main(List<String> args) async {
  LinkProvider link;
  List<Future> loadQueue = <Future>[];

  var server = new HttpProvider();

//  String basePath = Directory.current.path;

  link = new LinkProvider(args, "Schedule-", profiles: {
    AddICalRemoteScheduleNode.isType:
        (String path) => new AddICalRemoteScheduleNode(path, link),
    AddICalLocalScheduleNode.isType:
        (String path) => new AddICalLocalScheduleNode(path, link),
    ICalendarRemoteSchedule.isType:
        (String path) => new ICalendarRemoteSchedule(path, loadQueue, link),
    ICalendarLocalSchedule.isType:
        (String path) => new ICalendarLocalSchedule(path, loadQueue),
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider as MutableNodeProvider, onDelete: () {
      link.save();
    }),
    "event": (String path) => new EventNode(path),
    AddLocalEventNode.isType: (String path) => new AddLocalEventNode(path, link),
    HttpPortNode.isType: (String path) => new HttpPortNode(path, link, server),
    EditLocalEventNode.isType: (String path) => new EditLocalEventNode(path),
    FetchEventsNode.isType: (String path) => new FetchEventsNode(path),
    "fetchEventsForEvent": (String path) => new FetchEventsForEventNode(path),
    AddSpecialEventNode.isType: (String path) => new AddSpecialEventNode(path),
    FetchSpecialEventsNode.isType:
        (String path) => new FetchSpecialEventsNode(path),
    RemoveSpecialEventNode.isType:
        (String path) => new RemoveSpecialEventNode(path),
    TimezoneNode.isType: (String path) => new TimezoneNode(path, link)
  },
      defaultNodes: {
        AddICalRemoteScheduleNode.pathName: AddICalRemoteScheduleNode.def(),
        AddICalLocalScheduleNode.pathName: AddICalLocalScheduleNode.def(),
        HttpPortNode.pathName: HttpPortNode.def()
  },
      autoInitialize: false);

//  link.configure(optionsHandler: (opts) {
//    if (opts["base-path"] != null) {
//      basePath = opts["base-path"];
//    }
//  });

  try {
    await initializeTimeZone();
  } catch (e, stack) {
    logger.warning("Failed to load timezone data", e, stack);
  }

  setLocalLocation(await findTimezoneOnSystem());

  link.init();
  server.provider = link.provider as SimpleNodeProvider;

  var provider = link.provider as SimpleNodeProvider;
  if (!provider.nodes.containsKey("/${HttpPortNode.pathName}")) {
    link.addNode("/${HttpPortNode.pathName}", HttpPortNode.def());
  }

  var portValue = link.val("/${HttpPortNode.pathName}");
  await server.rebindHttpServer(portValue is String ? int.parse(portValue) : portValue);

  if (loadQueue.isNotEmpty) await Future.wait(loadQueue);
  loadQueue = null;

  link.connect();
}

class FetchEventsForEventNode extends SimpleNode {
  FetchEventsForEventNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    String timeRangeString = params["TimeRange"];
    DateTime start;
    DateTime end;

    {
      if (timeRangeString is String) {
        var parts = timeRangeString.split("/");
        start = DateTime.parse(parts[0]);
        end = DateTime.parse(parts[1]);
      }
    }
    var p = new Path(path);

    ICalendarLocalSchedule schedule = link.getNode(p.parent.parent.parent.path);
    String thatUuid = p.parent.name;

    var results = schedule.state.getBetween(start, end).where((v) => v.eventId == thatUuid).where((x) {
      return x.time.isAfter(start) && x.time.isBefore(end);
    }).toList();

    results.sort((a, b) => a.time.compareTo(b.time));

    results = results.map((v) {
      return [
        v.time.toIso8601String(),
        v.endsAt.toIso8601String(),
        v.duration.inMilliseconds,
        v.eventId,
        v.value
      ];
    }).toList();

    var list = [];
    var set = new Set();

    for (var x in results) {
      if (set.contains(x[0])) {
        continue;
      }
      set.add(x[0]);
      list.add(x);
    }

    return list;
  }
}
