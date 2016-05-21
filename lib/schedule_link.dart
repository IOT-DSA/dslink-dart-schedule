import 'dart:async';
import 'package:dslink/dslink.dart';
import 'nodes.dart';

class ScheduleDSLink {
  LinkProvider _linkProvider;

  ScheduleDSLink.withDefaultParams() {
    _linkProvider = new LinkProvider(
        ['b', 'http://localhost:8080/conn'], 'Schedule-',
        profiles: <String, dynamic>{
          AddRemoteCalendarNode.isType: (path) =>
              new AddRemoteCalendarNode(path)
        },
        defaultNodes: <String, dynamic>{
          AddRemoteCalendarNode.pathName: AddRemoteCalendarNode.definition()
        },
        isResponder: true,
        autoInitialize: false);
  }

  Future<Null> start() async {
    _linkProvider.init();

    await _linkProvider.connect();
  }
}
