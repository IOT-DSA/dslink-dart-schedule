import "package:timezone/standalone.dart";

main() async {
  await initializeTimeZone();
  var millis = timeZoneDatabase.get("America/New_York").translateToUtc(
    new DateTime.now().millisecondsSinceEpoch
  );

  print(new DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal());
}
