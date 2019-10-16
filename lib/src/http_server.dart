import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dslink/utils.dart';
import 'package:dslink/dslink.dart' show SimpleNodeProvider, SimpleNode;
import "package:path/path.dart" as pathlib;
import "package:xml/xml.dart" as xml;

import "package:dslink_schedule/ical.dart" as ical;
import 'package:dslink_schedule/utils.dart';
import 'nodes/local_schedules.dart' show ICalendarLocalSchedule;

abstract class _Consts {
  static const String description = 'DESCRIPTION';
  static const String dtstart = 'DTSTART';
  static const String dtend = 'DTEND';
  static const String uid = 'UID';
  static const String rrule = 'RRULE';
  static const String summary = 'SUMMARY';
  static const String vcalendar = 'VCALENDAR';
  static const String vevent = 'VEVENT';

  static const String href = 'href';
  static const String ns = 'DAV:';

  static final ContentType xml =
      new ContentType("application", "xml", charset: "utf-8");

  static const String rootQuery =
  '''<?xml version='1.0' encoding='UTF-8'?>
<multistatus xmlns='DAV:'>
  <response>
    <href>/</href>
    <propstat>
      <prop>
        <current-user-principal>
          <href>/principals/main/</href>
        </current-user-principal>
        <resourcetype>
          <collection/>
        </resourcetype>
      </prop>
      <status>HTTP/1.1 200 OK</status>
    </propstat>
  </response>
</multistatus>
  ''';
  static const String principalsMain =
  '''<?xml version='1.0' encoding='UTF-8'?>
<multistatus xmlns='DAV:'>
  <response>
    <href>/principals/main/</href>
    <propstat>
      <prop>
        <displayname>DSA</displayname>
        <B:calendar-home-set xmlns:B="urn:ietf:params:xml:ns:caldav">
          <href>/calendars/</href>
        </B:calendar-home-set>
      </prop>
      <status>HTTP/1.1 200 OK</status>
    </propstat>
  </response>
</multistatus>
  ''';

  static String forbidden(String path) => """
<?xml version='1.0' encoding='UTF-8'?>
<multistatus xmlns='DAV:'>
  <response>
    <href>$path</href>
    <propstat>
      <prop>
      </prop>
      <status>HTTP/1.1 403 Forbidden</status>
    </propstat>
  </response>
</multistatus>
    """;

  static const Map<String, String> calendarProperties = const {
    "PRODID": "PRODID:-//Distributed Services Architecture//Schedule DSLink//EN",
    "VERSION": "2.0",
    "CALSCALE": "GREGORIAN",
    "METHOD": "PUBLISH"
  };

  static const Map<String, dynamic> invalidInput = const {
    'ok': false,
    'error': const {
      'message': 'Invalid Input.',
      'code': 'http.calendar.invalid'
    }
  };
}

class HttpProvider {
  static HttpProvider _singleton;

  HttpServer server;
  SimpleNodeProvider provider;

  factory HttpProvider() {
    return _singleton ??= new HttpProvider._();
  }

  HttpProvider._();

  Future<Null> rebindHttpServer(int port) async {
    if (!port.isEven) return;

    if (server != null) {
      await server.close(force: true);
    }

    server = await HttpServer.bind('0.0.0.0', port);
    server.listen(handleHttpRequest, onError: (e, stack) {
      logger.warning('[HTTP] Error in server', e, stack);
    }, cancelOnError: false);
  }

  ICalendarLocalSchedule findLocalSchedule(String name) {
    if (name == null || name.isEmpty) return null;

    for (SimpleNode node in provider.nodes.values) {
      if (node is! ICalendarLocalSchedule) continue;

      if (name == node.displayName || node.path == "/$name") return node;
    }

    return null;
  }

  Future<Null> end(HttpResponse resp, dynamic output,
      {int status: HttpStatus.OK}) async {
    logger.fine("[Schedule HTTP] Reply with status code $status:\n$output");
    resp.statusCode = status;

    if (output is String) {
      resp.write(output);
    } else if (output is Uint8List) {
      resp.headers.contentType = ContentType.BINARY;
      resp.add(output);
    } else if (output is Map || output is List) {
      resp.headers.contentType = ContentType.JSON;
      resp.writeln(const JsonEncoder.withIndent("  ").convert(output));
    } else {
      logger.warning('[HTTP]: Unknown output type: ${output.runtimeType}.' +
          'Discarding message');
    }

    await resp.close();
  }
  
  Future<Null> sendNotFound(HttpResponse resp, String path) async {
    await end(resp, {
      "ok": false,
      "error": {
        "message": "$path was not found.",
        "code": "http.not.found"
      }
    }, status: HttpStatus.NOT_FOUND);
  }

  Future<Null> handleHttpRequest(HttpRequest req) async {
    HttpResponse resp = req.response;
    String path = req.uri.path;
    String method = req.method;
    var parts = pathlib.url.split(path);

    logger.fine("[Schedule HTTP] ${req.method} ${req.uri}");
    req.headers.forEach((a, b) {
      logger.fine("[Schedule HTTP] ${a}: ${req.headers.value(a)}");
    });

    resp.headers..set("DAV", "1, 2, calendar-access")
        ..set("Allow", 'OPTIONS, GET, HEAD, POST, PUT, DELETE, ' +
        'TRACE, COPY, MOVE, PROPFIND, PROPPATCH, LOCK, UNLOCK, REPORT, ACL');

    // Early escape invalid path.
    if (path == "/" && method != "PROPFIND") {
      return end(resp, {
        "ok": true,
        "response": {
          "message": "DSA Schedule Server"
        }
      });
    }

    switch (method) {
      case 'GET':
        return handleGetRequest(req, resp, path, parts);
      case 'PUT':
        return handlePutRequest(req, resp, path, parts);
      case 'PROPFIND':
        return handlePropFindRequest(req, resp, path, parts);
      case 'PROPPATCH':
        return handlePropPatchRequest(req, resp, path, parts);
      case 'OPTIONS':
        return handleOptionsRequest(req, resp, path, parts);
      case 'REPORT':
        return handleReportRequest(req, resp, path, parts);
    }

    return sendNotFound(resp, path);
  }

  Future<Null> handleGetRequest(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) async {

    if (parts.length < 3) {
      //TODO: probably end?
    }

    if (parts[1] != 'calendars') return sendNotFound(resp, path);

    switch (parts.length) {
    // GET: /calendars/something.ics
      case 3:
        var name = pathlib.basenameWithoutExtension(parts.last);
        var node = findLocalSchedule(name);

        if (node != null && node.generatedCalendar != null) {
          return end(resp, node.generatedCalendar);
        }
        return sendNotFound(resp, path);
      case 5:
        if (parts[3] != 'events') return sendNotFound(resp, path);
        if (parts.last.endsWith('.ics')) {
          var sched = findLocalSchedule(parts[2]);
          var evntName = pathlib.basenameWithoutExtension(parts[4]);
          if (sched != null && sched.generatedCalendar != null) {
            return _sendEvent(resp, path, sched, evntName);
          }
        }
        break;
    }

    return sendNotFound(resp, path);
  }

  Future<Null> _sendEvent(HttpResponse resp, String path,
      ICalendarLocalSchedule sched, String eventName) {
    List<Map> events = sched.storedEvents;
    var allEvents = sched
        .rootCalendarObject
        .properties[_Consts.vevent] as List<ical.CalendarObject>;
    ical.CalendarObject calObj;

    Map<String, dynamic> event = events.firstWhere((Map<String, dynamic> e) {
      return e['id'] == eventName || e['name'] == eventName;
    }, orElse: () => null);

    if (event == null) sendNotFound(resp, path);

    calObj = allEvents.firstWhere((ical.CalendarObject co) {
      return co.properties['UID'] == event['id'];
    }, orElse: () => null);

    var cal = new ical.CalendarObject();
    cal.type = _Consts.vcalendar;
    cal.properties.addAll(_Consts.calendarProperties);
    cal.properties[_Consts.vevent] = [calObj];
    var buff = new StringBuffer();
    ical.serializeCalendar(cal, buff);
    return end(resp, buff.toString());
  }

  Future<Null> handlePutRequest(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) async {
    if (parts.length != 5 || parts[1] != 'calendars') sendNotFound(resp, path);

    var sched = findLocalSchedule(parts[2]);
    String input = await UTF8.decodeStream(req);

    if (input.trim().isEmpty) return end(resp, 'Ok');

    var tokens = ical.tokenizeCalendar(input);
    ical.CalendarObject co = ical.parseCalendarObjects(tokens);
    List events = co.properties[_Consts.vevent];
    
    if (events is! List || events.isEmpty) {
      return end(resp, _Consts.invalidInput, status: HttpStatus.NOT_ACCEPTABLE);
    }
    
    List<Map> out = <Map>[];
    for (ical.CalendarObject e in events) {
      DateTime start = e.properties[_Consts.dtstart];
      DateTime end = e.properties[_Consts.dtend];
      String id = e.properties[_Consts.uid];

      var buff = new StringBuffer();
      ical.serializeCalendar(e.properties[_Consts.rrule], buff);
      String rule = buff.toString().trim();

      if (id == null) {
        id = generateToken();
      } else {
        // Remove existing ID if it exists.
        var ind = -1;
        for (var i = 0; i < sched.storedEvents.length; i++) {
          if (sched.storedEvents[i]['id'] == id) {
            ind = i;
            break;
          }
        }
        if (ind != -1) sched.storedEvents.removeAt(ind);
      }

      var map = { 'name': e.properties[_Consts.summary], 'id': id};

      if (start != null) map['start'] = start.toIso8601String();
      if (end != null) map['end'] = end.toIso8601String();
      if (rule != null && rule.isNotEmpty && rule != 'null') map['rule'] = rule;
      if (e.properties[_Consts.description] != null) {
        var desc = e.properties[_Consts.description];
        if (desc is Map && desc.length == 1 && desc.keys.single == 'value') {
          map['value'] = parseInputValue(desc['value']);
        } else {
          map['value'] = parseInputValue(desc);
        }
      }

      out.add(map);
    }

    sched.storedEvents.addAll(out);
    return end(resp, {}, status: HttpStatus.CREATED);
  }

  Future<Null> handlePropFindRequest(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) async {
    // PROPFIND /
    if (parts.length == 1 && parts.first == '/') {
      resp.headers.contentType = _Consts.xml;
      return end(resp, _Consts.rootQuery);
    }

    if (parts.length < 2) return sendNotFound(resp, path);

    // PROPFIND /calendars/<something>
    if (parts[1] == 'calendars') {
      return handleCalendarPropFind(req, resp, path, parts);
    }

    // PROPFIND /principals/main
    if (parts.length >= 3 && parts[1] == 'principals' && parts[2] == 'main') {
//      var input = await UTF8.decodeStream(req); // TODO: (mbutler) Why?
      await req.drain();
      resp.headers.contentType = _Consts.xml;
      return end(resp, _Consts.principalsMain, status: 207);
    }

    return sendNotFound(resp, path);
  }

  Future<Null> handleCalendarPropFind(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) async {
    String name = parts.length >= 3 ? parts[2] : null;
    ICalendarLocalSchedule sched = findLocalSchedule(name);

    var input = await UTF8.decodeStream(req);
    if (input.trim().isEmpty) return end(resp, 'Ok.');

    logger.fine('[Schedule HTTP] Sent ${req.method} to $path:\n$input');

    xml.XmlDocument doc = xml.parse(input);
    xml.XmlElement prop =
        doc.rootElement.findElements('prop', namespace: 'DAV:').first;

    resp.headers.contentType = _Consts.xml;
    if (sched != null) {
      resp.headers.set(HttpHeaders.ETAG, sched.calculateTag());
      var pd = ParsedData.fromXml(prop, sched, path, req.requestedUri);
      return end(resp, pd.buildOutput(req), status: 207);
    }

    Iterable<ParsedData> all = provider.nodes.values
        .where((nd) => nd is ICalendarLocalSchedule)
        .map((ICalendarLocalSchedule node) =>
            ParsedData.fromXml(prop, node, path, req.requestedUri));

    return end(resp, ParsedData.buildMultiOutput(all), status: 207);
  }

  Future<Null> handlePropPatchRequest(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) async {
    await req.drain();

    resp.headers.contentType = _Consts.xml;
    await end(resp, _Consts.forbidden(path), status: 207);
  }

  Future<Null> handleOptionsRequest(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) => end(resp, 'Ok.');

  Future<Null> handleReportRequest(HttpRequest req, HttpResponse resp,
      String path, List<String> parts) async {
    var input = await UTF8.decodeStream(req);
    logger.fine('[Schedule HTTP] Report Received - $input');

    if (parts.length < 3) sendNotFound(resp, path);
    var name = parts[2];
    var sched = findLocalSchedule(name);

    var out = new xml.XmlBuilder();
    out.processing('xml', 'version="1.0" encoding="utf-8"');
    out.element('multistatus', namespace: _Consts.ns, namespaces: {
      _Consts.ns: '',
      "urn:ietf:params:xml:ns:caldav": "c"
    }, nest: () {
      out.element('response', namespace: _Consts.ns, nest: () {
        out.element(_Consts.href, namespace: _Consts.ns, nest: '/calendars/$name.ics');
        out.element('propstat', namespace: _Consts.ns, nest: () {
          out.element('prop', nest: () {
            out.element('getcontenttype', namespace: _Consts.ns, 
                nest: 'text/calendar; component=vevent');
            out.element('getetag', namespace: _Consts.ns, nest: sched.calculateTag());
            
            if (input.contains('calendar-data')) {
              out.element('calendar-data',
                  namespace: 'urn:ietf:params:xml:ns:caldav',
                  nest: sched.generatedCalendar);
            }
          });

          out.element('status', namespace: _Consts.ns, nest: 'HTTP/1.1 200 OK');
        });
      });
    });

    return end(resp, out.build().toXmlString(pretty: true), status: 207);
  }
}

class ParsedData {
  final String path;
  final ICalendarLocalSchedule sched;

  Uri syncToken;
  Map<xml.XmlName, dynamic> results;
  List<xml.XmlName> notOut;

  ParsedData(this.sched, this.path, Uri uri) {
    results = new Map<xml.XmlName, dynamic>();
    notOut = new List<xml.XmlName>();

    var path = pathlib.join(uri.path, 'sync') + '/${generateToken()}';
    syncToken = uri.replace(path: path);
  }

  static ParsedData fromXml(xml.XmlElement el, ICalendarLocalSchedule sched,
      String path, Uri uri) {
    var pd = new ParsedData(sched, path, uri);
    for (xml.XmlElement e in el.children.where((x) => x is xml.XmlElement)) {
      var name = e.name.local;

      var res = pd._checkName(name);
      if (res != null) {
        pd.results[e.name] = res;
      } else {
        pd.notOut.add(e.name);
      }
    }

    return pd;
  }

  static String buildMultiOutput(Iterable<ParsedData> dataSet) {
    if (dataSet.isEmpty) return null;
    var first = dataSet.first;

    var out = new xml.XmlBuilder();

    out.processing('xml', 'version="1.0" encoding="utf-8"');
    out.element('multistatus', namespace: _Consts.ns, namespaces: {
      _Consts.ns: '',
      "http://calendarserver.org/ns/": "CS",
      "urn:ietf:params:xml:ns:caldav": "C"
    }, nest: () {
      out.element('response', namespace: _Consts.ns, nest: () {
        out.element(_Consts.href, namespace: _Consts.ns, nest: first.path);

        out.element('propstat', namespace: _Consts.ns, nest: () {
          out.element('prop', namespace: _Consts.ns, nest: () {
            out.element('resourcetype', namespace: _Consts.ns, nest: () {
              out.element('collection', namespace: _Consts.ns);
            });
          });
          out.element('status', namespace: _Consts.ns, nest: 'HTTP/1.1 200 OK');
        });
      }); // End 1st response element

      for (var data in dataSet) {
        out.element('response', namespace: _Consts.ns, nest:
          data._buildResponse(out, name: '/calendars/${data.sched.displayName}'));
      }
    });

    return out.build().toXmlString(pretty: true);
  }

  dynamic _checkName(String name) {
    switch(name) {
      case 'displayname':
      case 'calendar-description':
        return sched.displayName;
      case 'getctag':
      case 'getetag':
        return sched.calculateTag();
      case 'getcontenttype':
        return 'text/calendar; component=vevent';
      case 'calendar-home-set':
        return (xml.XmlBuilder out) {
          out.element("href", namespace: "DAV:",
              nest: pathlib.join(
                  pathlib.dirname(path), pathlib.basename(path) + "/"));
        };
      case 'current-user-principal':
      case 'calendar-user-address-set':
        return (xml.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/principals/main/");
        };
      case 'supported-report-set':
        return (xml.XmlBuilder out) {
          out.element(
            "supported-report", namespace: "urn:ietf:params:xml:ns:caldav",
            nest: () {
              out.element("report", namespace: "urn:ietf:params:xml:ns:caldav",
                nest: 'calendar-query');
            });
        };
      case 'calendar-collection-set':
        return (xml.XmlBuilder out) {
          out.element("href", nest: sched.displayName);
        };
      case 'principal-collection-set':
        return (xml.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/");
        };
      case 'supported-calendar-component-set':
        return (xml.XmlBuilder out) {
          out.element("comp", namespace: "urn:ietf:params:xml:ns:caldav",
              attributes: {"name": "VEVENT"});
        };
      case 'sync-token':
        return syncToken.toString();
      case 'resourcetype':
        return (xml.XmlBuilder out) {
          out.element("calendar", namespace: "urn:ietf:params:xml:ns:caldav");
        };
      case 'sync-level':
        return '1';
      case 'owner':
      case 'source':
        return (xml.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: path);
        };
      case 'calendar-color':
        return 'FF5800';
    }

    return null;
  }

  String buildOutput(HttpRequest req) {
    xml.XmlBuilder out = new xml.XmlBuilder();
    out.processing('xml', 'version="1.0" encoding="utf-8"');
    out.element('multistatus', namespace: _Consts.ns, namespaces: {
      _Consts.ns: '',
      "http://calendarserver.org/ns/": "CS",
      "urn:ietf:params:xml:ns:caldav": "C"
    }, nest: () {
      out.element(_Consts.href, namespace: _Consts.ns, nest:
          pathlib.join(pathlib.dirname(path), pathlib.basename(path) + '.ics'));
      out.element(
          'sync-token', namespace: _Consts.ns, nest: syncToken.toString());
      out.element('response', namespace: _Consts.ns, nest: _buildResponse(out));
      if (req.headers.value('depth') != '0') {
        out.element(
            'response', namespace: _Consts.ns, nest: _buildDepthResponse(out));
      }
    });

    return out.build().toXmlString(pretty: true);
  }

  Function _buildResponse(xml.XmlBuilder out, {String name}) {
    var path = name ?? this.path;
    return () {
      out.element(_Consts.href, namespace: _Consts.ns, nest: path);
      out.element('propstat', namespace: _Consts.ns, nest: () {
        out.element('prop', namespace: _Consts.ns, nest: _buildProps(out));
        out.element("status", namespace: _Consts.ns, nest: "HTTP/1.1 200 OK");
      });
      out.element('propstat', namespace: _Consts.ns, nest: () {
        out.element('prop', namespace: _Consts.ns, nest: _buildNotProps(out));
        out.element(
            "status", namespace: _Consts.ns, nest: "HTTP/1.1 404 Not Found");
      });
    };
  }

  Function _buildProps(xml.XmlBuilder out) {
    return () {
      for (xml.XmlName key in results.keys) {
        String ns;
        switch (key.local) {
          case 'getctag':
            ns = 'http://calendarserver.org/ns/';
            break;
          case 'supported-calendar-component-set':
            ns = 'urn:ietf:params:xml:ns:caldav';
            break;
          default:
            ns = _Consts.ns;
        }

        var value = results[key];
        out.element(key.local, namespace: ns, nest: () {
          if (value is String || value is num) {
            out.text(value);
          } else if (value is Function) {
            value(out);
          }
        });
      }
    };
  }

  Function _buildNotProps(xml.XmlBuilder out) {
    return () {
      for (xml.XmlName key in notOut) {
        if (key.local == 'principal-URL' ||
            key.local == 'current-user-principal') {
          out.element(key.local, namespace: key.namespaceUri, nest: () {
            out.element('unauthenticated', namespace: _Consts.ns);
          });
          continue;
        }

        if (key.prefix == null) {
          out.element(key.local);
          continue;
        }

        if (key.namespaceUri != _Consts.ns &&
            key.namespaceUri != "http://calendarserver.org/ns/") {
          try {
            out.namespace(key.namespaceUri, key.prefix);
          } catch (_) {
            // Empty
          }
        }

        out.element(key.local, namespace: key.namespaceUri);
      } // end for
    };
  }

  Function _buildDepthResponse(xml.XmlBuilder out) {
    return () {
      const keyNames =
      const ['resourcetype', 'getcontentype', 'getetag', 'sync-token'];

      out.element('propstat', namespace: _Consts.ns, nest: () {
        for (xml.XmlName key in results.keys) {
          if (!keyNames.contains(key.local)) continue;

          var value = results[key];
          out.element(key.local, namespace: _Consts.ns, nest: () {
            if (key.local == 'resourcetype') return;
            if (value is String || value is num) {
              out.text(value);
            } else if (value is Function) {
              value(out);
            }
          });
        }

        out.element('status', namespace: _Consts.ns, nest: 'HTTP/1.1 200 OK');
      });
    };
  }
}
