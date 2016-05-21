import 'dart:async';
import 'package:dslink/dslink.dart';
import 'nodes.dart';
import 'package:di/di.dart';
import 'modules.dart';

class ScheduleDSLink {
  LinkProvider _linkProvider;
  ModuleInjector _injector;

  ScheduleDSLink.withDefaultParams() {
    _injector = new ModuleInjector([diModule]);

    _linkProvider = new LinkProvider(
        ['b', 'http://localhost:8080/conn'], 'Schedule-',
        profiles: <String, NodeFactory>{
          AddRemoteCalendarNode.isType: (path) =>
              new AddRemoteCalendarNode(path, _injector)
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
