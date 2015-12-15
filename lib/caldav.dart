library dslink.schedule.caldav;

import "dart:async";
import "dart:io";
import "dart:convert";
import "dart:typed_data";

import "package:xml/xml.dart" hide parse;
import "package:xml/xml.dart" as XML;

import "main.dart";

typedef EndResponse(input, {int status: HttpStatus.OK});

Future handleCalDavRequest(HttpRequest request) async {
  HttpResponse response = request.response;

  end(input, {int status: HttpStatus.OK}) async {
    response.statusCode = status;

    if (input is String) {
      response.write(input);
    } else if (input is Uint8List) {
      response.headers.contentType = ContentType.BINARY;
      response.add(input);
    } else if (input is Map || input is List) {
      response.headers.contentType = ContentType.JSON;
      response.writeln(const JsonEncoder.withIndent("  ").convert(input));
    } else {
    }

    await response.close();
  }

  if (request.method == "PROPFIND") {
  }
}

Future handleCalDavPropFind(HttpRequest request, HttpResponse response, EndResponse end) async {
  String path = request.uri.path;
  String method = request.method;
  String out = "";
  String input = request
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())
      .join("\n");

  List<String> parts = path.split("/");

  XmlDocument doc = XML.parse(input);
  String basePath = parts.skip(2).join("/");
}
