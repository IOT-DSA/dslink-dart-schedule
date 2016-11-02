import "package:timezone/standalone.dart";

main() {
  initializeTimeZoneSync();
  var millis = timeZoneDatabase.get("America/New_York").translateToUtc(
    new DateTime.now().millisecondsSinceEpoch
  );

  print(new DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal());
}
