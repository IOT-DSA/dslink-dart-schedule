import 'dart:async';
import 'dart:io';

import 'package:dslink/dslink.dart';
import 'package:dslink/utils.dart';

class HttpPortNode extends SimpleNode {
  static const String pathName = "httpPort";
  static const String isType = "httpPort";

  final LinkProvider _link;
  HttpPortNode(String path, this._link) : super(path);

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
      rebindHttpServer(port);
      _link.save();
      return false;
    } else {
      return false;
    }
  }
}