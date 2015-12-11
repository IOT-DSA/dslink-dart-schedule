import "dart:io";
import "package:package_config/packages.dart";
import "package:package_config/discovery.dart";

main() async  {
  var file = new File(".packages");
  Packages pkgs = await loadPackagesFile(file.absolute.uri);
  Map map = pkgs.asMap();
  var out = new StringBuffer();

  for (var pkg in map.keys) {
    if (pkg == "dslink_schedule") {
      out.writeln("${pkg}:lib/");
    } else {
      out.writeln("${pkg}:packages/${pkg}/");
    }
  }

  var outFile = new File("build/.packages");
  await outFile.writeAsString(out.toString());
}
