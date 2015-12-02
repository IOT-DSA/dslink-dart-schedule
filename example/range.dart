main() {
  var now = new DateTime.now();
  var threeMinutesFromNow = now.add(const Duration(minutes: 3));
  var fiveMinutesFromNow = threeMinutesFromNow.add(const Duration(minutes: 2));
  print(threeMinutesFromNow);
  print(fiveMinutesFromNow);
}
