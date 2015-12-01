library dslink.schedule.tz;

import "dart:async";
import "dart:io";

import "package:timezone/standalone.dart";
import "package:timezone/src/tzdb.dart";

Future<Location> findTimezoneOnSystem() async {
  var file = new File("/etc/localtime");

  if (!(await file.exists())) {
    return null;
  }

  var bytes = await file.readAsBytes();
  var locations = tzdbDeserialize(bytes);
  if (locations.isEmpty) {
    return null;
  }
  var location = locations.first;
  return location;
}

String buildICalTimezoneSection(Location location) {
  var standardZone = location.zones.firstWhere((x) => !x.isDst, orElse: () => null);
  var daylightZone = location.zones.firstWhere((x) => x.isDst, orElse: () => null);

  var lines = [
    "BEGIN:VTIMEZONE",
    "TZID:${location.name}",
    "X-LIC-LOCATION:${location.name}"
  ];

  if (daylightZone != null && standardZone != null) {
    String from = standardZone.offset.abs().toString().padLeft(4, "0");
    String to = daylightZone.offset.abs().toString().padLeft(4, "0");

    if (standardZone.offset.isNegative) {
      from = "-${from}";
    } else {
      from = "+${from}";
    }

    if (daylightZone.offset.isNegative) {
      to = "-${to}";
    } else {
      to = "+${to}";
    }

    lines.addAll([
      "BEGIN:DAYLIGHT",
      "TZOFFSETFROM:${from}",
      "TZOFFSETTO:${to}",
      "TZNAME:${daylightZone.abbr}",
      "END:DAYLIGHT"
    ]);

    lines.addAll([
      "BEGIN:STANDARD",
      "TZOFFSETFROM:${to}",
      "TZOFFSETTO:${from}",
      "TZNAME:${standardZone.abbr}",
      "END:STANDARD"
    ]);
  }

  lines.add("END:VTIMEZONE");

  return lines.join("\n");
}
