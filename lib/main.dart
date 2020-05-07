library dslink.schedule.main;

import "dart:async";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import 'package:timezone/standalone.dart';

import 'package:dslink_schedule/nodes.dart';
import "package:dslink_schedule/tz.dart";

import 'package:dslink_schedule/src/http_server.dart';

LinkProvider link;
//http.Client httpClient = new http.Client();
//SimpleNodeProvider provider;

main(List<String> args) async {
  LinkProvider link;
  List<Future> loadQueue = <Future>[];

  var server = new HttpProvider();

//  String basePath = Directory.current.path;

  link = new LinkProvider(args, "Schedule-", profiles: {
    // New ones
    AddSchedule.isType: (String path) => new AddSchedule(path, link),
    ScheduleNode.isType: (String path) => new ScheduleNode(path, link),
    DefaultValueNode.isType: (String path) => new DefaultValueNode(path),
    ExportSchedule.isType: (String path) => new ExportSchedule(path),
    ImportSchedule.isType: (String path) => new ImportSchedule(path, link),
    EventsNode.isType: (String path) => new EventsNode(path),
    AddSingleEvent.isType: (String path) => new AddSingleEvent(path, link),
    AddMomentEvent.isType: (String path) => new AddMomentEvent(path, link),
    AddRecurringEvents.isType: (String path) => new AddRecurringEvents(path, link),
    RemoveAction.isType: (String path) => new RemoveAction(path),
    EditEvent.isType: (String path) => new EditEvent(path, link),
    EventDateTime.isType: (String path) => new EventDateTime(path),
    EventFrequency.isType: (String path) => new EventFrequency(path),
    EventValue.isType: (String path) => new EventValue(path),
    EventIsSpecial.isType: (String path) => new EventIsSpecial(path),
    EventPriority.isType: (String path) => new EventPriority(path),
    // DataNodes for the schedule link. Specially requested by Pavel O.
    DataRootNode.isType: (String path) => new DataRootNode(path),
    DataNode.isType: (String path) => new DataNode(path, link),
    DataAddNode.isType: (String path) => new DataAddNode(path, link),
    DataRemove.isType: (String path) => new DataRemove(path, link),
    DataAddValue.isType: (String path) => new DataAddValue(path, link),
    DataPublish.isType: (String path) => new DataPublish(path, link),

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
    EventNode.isType: (String path) => new EventNode(path),
    AddLocalEventNode.isType: (String path) => new AddLocalEventNode(path, link),
    HttpPortNode.isType: (String path) => new HttpPortNode(path, link, server),
    EditLocalEventNode.isType: (String path) => new EditLocalEventNode(path),
    FetchEventsNode.isType: (String path) => new FetchEventsNode(path),
    FetchEventsForEventNode.isType:
        (String path) => new FetchEventsForEventNode(path),
    AddSpecialEventNode.isType: (String path) => new AddSpecialEventNode(path),
    FetchSpecialEventsNode.isType:
        (String path) => new FetchSpecialEventsNode(path),
    RemoveSpecialEventNode.isType:
        (String path) => new RemoveSpecialEventNode(path, link),
    TimezoneNode.isType: (String path) => new TimezoneNode(path, link)
  },
      defaultNodes: {
        AddSchedule.pathName: AddSchedule.def(),
        ImportSchedule.pathName: ImportSchedule.def(),
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

  //var provider = link.provider as SimpleNodeProvider;
  _addMissing(link, "/${HttpPortNode.pathName}", HttpPortNode.def());
  _addMissing(link, "/${DataRootNode.pathName}", DataRootNode.def());
  _addMissing(link, '/${AddSchedule.pathName}', AddSchedule.def());
  _addMissing(link, '/${ImportSchedule.pathName}', ImportSchedule.def());

  var portValue = link.val("/${HttpPortNode.pathName}");
  await server.rebindHttpServer(portValue is String ? int.parse(portValue) : portValue);

  if (loadQueue.isNotEmpty) await Future.wait(loadQueue);
  loadQueue = null;

  link.connect();
}

void _addMissing(LinkProvider link, String path, Map<String, dynamic> map) {
  var provider = link.provider as SimpleNodeProvider;
  var nd = provider.getNode(path);
  if (nd == null) {
    link.addNode(path, map);
  }
}
