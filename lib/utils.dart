library dslink.schedule.utils;

dynamic parseInputValue(input) {
  if (input == null) return null;

  if (input is! String) {
    return input;
  }

  var lowerTrimmed = input.trim().toLowerCase();

  if (lowerTrimmed == "true" || lowerTrimmed == "false") {
    return lowerTrimmed == "true";
  }

  var number = num.parse(input, (source) => null);

  if (number != null) {
    return number;
  }

  return input;
}
