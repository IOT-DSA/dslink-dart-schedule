import 'package:dslink/dslink.dart';

import '../http_server.dart';

class HttpPortNode extends SimpleNode {
  static const String pathName = "httpPort";
  static const String isType = "httpPort";

  final LinkProvider _link;
  final HttpProvider server;
  HttpPortNode(String path, this._link, this.server) : super(path);

  static Map<String, dynamic> def() => {
    r'$is': isType,
    r"$name": "HTTP Port",
    r"$type": "int",
    r"$writable": "write",
    "?value": -1
  };

  @override
  onSetValue(dynamic val) {
    if (val is String) {
      try {
        val = num.parse(val);
      } catch (e) {}
    }

    if (val is num && !val.isNaN && (val > 0 || val == -1)) {
      var port = val.toInt();
      updateValue(port);
      server.rebindHttpServer(port);
      _link.save();
      return false;
    } else {
      return false;
    }
  }
}