import 'package:dslink/dslink.dart';
import 'package:dslink_schedule/calendar.dart';

import 'common.dart';

class EventNode extends SimpleNode {
  static const String isType = 'event';

  EventDescription description;
  bool flagged = false;

  EventNode(String path) : super(path);

  @override
  onRemoving() {
    var p = new Path(path);
    var node = provider.getNode(p.parent.parent.path);
    if (node is ICalendarLocalSchedule && !flagged) {
      node.removeStoredEvent(description.name);
    }
  }

  @override
  void load(Map input) {
    if (input["?description"] is EventDescription) {
      description = input["?description"];
    }
    super.load(input);
  }
}