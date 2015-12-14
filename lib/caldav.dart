library dslink.schedule.caldav;

import "dart:io";

import "package:xml/xml.dart";

class CalResponse {
  Map<XmlName, dynamic> results = {};

  XmlNode build() {
    var out = new XmlBuilder();
    out.element("propstat", namespace: "DAV:", namespaces: {
      "DAV:": ""
    }, nest: () {

    });
  }
}

XmlDocument handleMultiStatus(HttpRequest request, List<CalResponse> responses) {
  var text = MULTISTATUS_TEXT;
  text = text.replaceAll("{{PATH}}", request.uri.path);
  text = text.replaceAll("{{PROPS}}", responses.map((x) => x.build().toXmlString()).join());
  return parse(text);
}

const String MULTISTATUS_TEXT = """
<d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
    <d:response>
      <d:href>{{PATH}}</d:href>
      {{PROPS}}
    </d:response>
</d:multistatus>
""";
