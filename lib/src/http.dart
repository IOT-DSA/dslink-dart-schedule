part of dslink.schedule.main;

handleHttpRequest(HttpRequest request) async {
  logger.fine("[Schedule HTTP] ${request.method} ${request.uri}");
  request.headers.forEach((a, b) {
    logger.fine("[Schedule HTTP] ${a}: ${request.headers.value(a)}");
  });

  HttpResponse response = request.response;
  String path = request.uri.path;
  String method = request.method;

  end(input, {int status: HttpStatus.OK}) async {
    logger.fine("[Schedule HTTP] Reply with status code ${status}:\n${input}");
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

  sendNotFound() async {
    await end({
      "ok": false,
      "error": {
        "message": "${path} was not found.",
        "code": "http.not.found"
      }
    }, status: HttpStatus.NOT_FOUND);
  }

  var parts = pathlib.url.split(path);

  response.headers.set("DAV", "1, 2, calendar-access");
  response.headers.set("Allow", "OPTIONS, GET, HEAD, POST, PUT, DELETE, TRACE, COPY, MOVE, PROPFIND, PROPPATCH, LOCK, UNLOCK, REPORT, ACL");

  if (method != "PROPFIND" && path == "/") {
    await end({
      "ok": true,
      "response": {
        "message": "DSA Schedule Server"
      }
    });
    return;
  } else if (method == "GET" &&
    parts.length == 3 &&
    parts[1] == "calendars" &&
    pathlib.extension(path) == ".ics") {
    var name = pathlib.basenameWithoutExtension(parts[2]);
    var node = findLocalSchedule(name);
    if (node != null && node.generatedCalendar != null) {
      await end(node.generatedCalendar);
      return;
    }
  } else if (method == "PROPFIND" && path == "/") {
    response.headers.contentType =
      ContentType.parse("application/xml; charset=utf-8");
    await end("""
<?xml version='1.0' encoding='UTF-8'?>
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
    """, status: 207);
    return;
  } else if (method == "PROPFIND" && path == "/principals/main/") {
    var input = await request
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())
      .join("\n");
    response.headers.contentType =
      ContentType.parse("application/xml; charset=utf-8");
    await end("""
<?xml version='1.0' encoding='UTF-8'?>
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
    """, status: 207);
    return;
  } else if (parts.length == 5 &&
    parts[1] == "calendars" &&
    parts[3] == "events" &&
    parts[4].endsWith(".ics")) {
    var node = findLocalSchedule(parts[2]);
    var name = pathlib.basenameWithoutExtension(parts[4]);
    if (node != null && node.generatedCalendar != null) {
      if (method == "GET") {
        List<Map> events = node.storedEvents;
        for (var x in events) {
          if (x["id"] == name || x["name"] == name) {
            var allEvents = node.rootCalendarObject.properties["VEVENT"];
            ical.CalendarObject event;

            for (ical.CalendarObject t in allEvents) {
              if (t.properties["UID"] == x["id"]) {
                event = t;
              }
            }

            var cal = new ical.CalendarObject();
            cal.type = "VCALENDAR";
            cal.properties.addAll({
              "PRODID": "PRODID:-//Distributed Services Architecture//Schedule DSLink//EN",
              "VERSION": "2.0",
              "CALSCALE": "GREGORIAN",
              "METHOD": "PUBLISH"
            });
            cal.properties["VEVENT"] = [event];
            var buff = new StringBuffer();
            ical.serializeCalendar(cal, buff);
            await end(buff.toString());
            return;
          }
        }
      }
    }

    if (method == "PUT") {
      String input = await request
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .join("\n");

      if (input.isEmpty) {
        await end("Ok.");
        return;
      }

      var tokens = ical.tokenizeCalendar(input);
      ical.CalendarObject obj = ical.parseCalendarObjects(tokens);
      List events = obj.properties["VEVENT"];
      if (events is! List || events.isEmpty) {
        await end({
          "ok": false,
          "error": {
            "message": "Invalid Input.",
            "code": "http.calendar.invalid"
          }
        }, status: HttpStatus.NOT_ACCEPTABLE);
        return;
      }

      List<Map> out = [];

      for (ical.CalendarObject x in events) {
        DateTime startTime = x.properties["DTSTART"];
        DateTime endTime = x.properties["DTEND"];
        String id = x.properties["UID"];
        var buff = new StringBuffer();
        ical.serializeCalendar(x.properties["RRULE"], buff);
        String rule = buff.toString();

        if (id == null) {
          id = generateToken();
        }

        var map = {
          "name": x.properties["SUMMARY"],
          "id": id
        };

        if (startTime != null) {
          map["start"] = startTime.toIso8601String();
        }

        if (endTime != null) {
          map["end"] = endTime.toIso8601String();
        }

        if (rule != null && rule != "null\n" && rule != "null") {
          map["rule"] = rule;
        }

        if (x.properties["DESCRIPTION"] != null) {
          var desc = x.properties["DESCRIPTION"];
          if (desc is Map && desc.keys.length == 1 && desc.keys.single == "value") {
            desc = parseInputValue(desc["value"]);
          }
          map["value"] = parseInputValue(desc);
        }

        out.add(map);
      }

      ml: for (var e in node.storedEvents.toList()) {
        for (var l in out) {
          if (e["id"] == l["id"]) {
            node.storedEvents.remove(e);
            continue ml;
          }
        }
      }

      node.storedEvents.addAll(out);
      await node.loadSchedule();
      await end({}, status: HttpStatus.CREATED);
      return;
    }
  } else if (path.startsWith("/calendars/") && path != "/calendars/" && parts.length >= 2 && (method == "PROPFIND")) {
    String name;
    if (parts.length >= 3) {
      name = parts[2];
    } else {
      name = "";
    }

    ICalendarLocalSchedule schedule = findLocalSchedule(name);

    if (name.isEmpty || schedule == null) {
      await sendNotFound();
      return;
    }

    response.headers.set("ETag", schedule.calculateTag());

    var input = await request
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())
      .join("\n");

    if (input.isEmpty) {
      await end("Ok.");
      return;
    }

    logger.fine("[Schedule HTTP] Sent ${request.method} to ${path}:\n${input}");

    XML.XmlDocument doc = XML.parse(input);
    XML.XmlElement prop = doc.rootElement
      .findElements("prop", namespace: "DAV:")
      .first;

    var results = <XML.XmlName, dynamic>{};
    var out = new XML.XmlBuilder();

    var notOut = [];

    Uri syncTokenUri = request.requestedUri;
    syncTokenUri = syncTokenUri
      .replace(path: pathlib.join(syncTokenUri.path, "sync") + "/${generateToken()}");
    for (XML.XmlElement e in prop.children.where((x) => x is XML.XmlElement)) {
      var name = e.name.local;

      if (name == "displayname") {
        results[e.name] = schedule.displayName;
      } else if (name == "getctag" || name == "getetag") {
        results[e.name] = schedule.calculateTag();
      } else if (name == "principal-URL" && false) {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/");
        };
      } else if (name == "getcontenttype") {
        results[e.name] = (XML.XmlBuilder out) {
          out.text("text/calendar; component=vevent");
        };
      } else if (name == "calendar-home-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:",
            nest: pathlib.join(
              pathlib.dirname(path), pathlib.basename(path) + "/"));
        };
      } else if (name == "current-user-principal" && false) {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/principals/main/");
        };
      } else if (name == "calendar-user-address-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/principals/main/");
        };
      } else if (name == "supported-report-set") {
        results[e.name] = (XML.XmlBuilder out) {
          for (var name in const ["calendar-query"]) {
            out.element(
              "supported-report", namespace: "urn:ietf:params:xml:ns:caldav",
              nest: () {
                out.element(
                  "report", namespace: "urn:ietf:params:xml:ns:caldav",
                  nest: name);
              });
          }
        };
      } else if (name == "calendar-collection-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", nest: schedule.displayName);
        };
      } else if (name == "principal-collection-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: "/");
        };
      } else if (name == "supported-calendar-component-set") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element(
            "comp", namespace: "urn:ietf:params:xml:ns:caldav", attributes: {
            "name": "VEVENT"
          });
        };
      } else if (name == "sync-token") {
        results[e.name] = (XML.XmlBuilder out) {
          out.text(syncTokenUri.toString());
        };
      } else if (name == "resourcetype") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("calendar", namespace: "urn:ietf:params:xml:ns:caldav");
        };
      } else if (name == "sync-level") {
        results[e.name] = "1";
      } else if (name == "owner" || name == "source") {
        results[e.name] = (XML.XmlBuilder out) {
          out.element("href", namespace: "DAV:", nest: path);
        };
      } else if (name == "calendar-description") {
        results[e.name] = schedule.displayName;
      } else if (name == "calendar-color") {
        results[e.name] = "FF5800";
      } else {
        notOut.add(e.name);
      }
    }

    response.headers.contentType =
      ContentType.parse("application/xml; charset=utf-8");

    out.processing("xml", 'version="1.0" encoding="utf-8"');

    out.element("multistatus", namespace: "DAV:", namespaces: {
      "DAV:": "",
      "http://calendarserver.org/ns/": "CS",
      "urn:ietf:params:xml:ns:caldav": "C"
    }, nest: () {
      out.element("href", namespace: "DAV:",
        nest: pathlib.join(
          pathlib.dirname(path), pathlib.basename(path) + ".ics"));
      out.element("sync-token", namespace: "DAV:",
        nest: syncTokenUri.toString());
      out.element("response", namespace: "DAV:", nest: () {
        out.element("href", namespace: "DAV:", nest: path);
        out.element("propstat", namespace: "DAV:", nest: () {
          out.element("prop", namespace: "DAV:", nest: () {
            for (XML.XmlName key in results.keys) {
              String ns = "DAV:";
              if (key.local == "getctag") {
                ns = "http://calendarserver.org/ns/";
              }

              if (key.local == "supported-calendar-component-set") {
                ns = "urn:ietf:params:xml:ns:caldav";
              }

              out.element(key.local, namespace: ns, nest: () {
                if (results[key] is String || results[key] is num) {
                  out.text(results[key]);
                } else if (results[key] is Function) {
                  results[key](out);
                }
              });
            }
          });


          out.element("status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
        });

        out.element("propstat", namespace: "DAV:", nest: () {
          out.element("prop", namespace: "DAV:", nest: () {
            for (XML.XmlName key in notOut) {
              if (key.local == "principal-URL" ||
                key.local == "current-user-principal") {
                out.element(key.local, namespace: key.namespaceUri, nest: () {
                  out.element("unauthenticated", namespace: "DAV:");
                });
              } else if (key.prefix != null) {
                if (key.namespaceUri != "DAV:" &&
                  key.namespaceUri != "http://calendarserver.org/ns/") {
                  try {
                    out.namespace(key.namespaceUri, key.prefix);
                  } catch (e) {}
                }

                out.element(key.local, namespace: key.namespaceUri);
              } else {
                out.element(key.local);
              }
            }
          });

          out.element(
            "status", namespace: "DAV:", nest: "HTTP/1.1 404 Not Found");
        });
      });

      if (request.headers.value("depth") != "0") {
        out.element("response", namespace: "DAV:", nest: () {
          out.element("propstat", namespace: "DAV:", nest: () {
            for (XML.XmlName key in results.keys) {
              if (!(const ["resourcetype", "getcontentype", "getetag", "sync-token"].contains(
                key.local))) {
                continue;
              }

              out.element(key.local, namespace: "DAV:", nest: () {
                if (key.local != "resourcetype") {
                  if (results[key] is String || results[key] is num) {
                    out.text(results[key]);
                  } else if (results[key] is Function) {
                    results[key](out);
                  }
                }
              });
            }

            out.element(
              "status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
          });
        });
      }
    });

    await end(out.build().toXmlString(pretty: true), status: 207);
    return;
  } else if (path == "/calendars/" && (method == "PROPFIND")) {
    var input = await request
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())
      .join("\n");

    if (input.isEmpty) {
      await end("Ok.");
      return;
    }

    logger.fine("[Schedule HTTP] Sent ${request.method} to ${path}:\n${input}");

    XML.XmlDocument doc = XML.parse(input);
    XML.XmlElement prop = doc.rootElement
      .findElements("prop", namespace: "DAV:")
      .first;

    var results = <XML.XmlName, dynamic>{};
    var out = new XML.XmlBuilder();

    response.headers.contentType =
      ContentType.parse("application/xml; charset=utf-8");

    out.processing("xml", 'version="1.0" encoding="utf-8"');

    out.element("multistatus", namespace: "DAV:", namespaces: {
      "DAV:": "",
      "http://calendarserver.org/ns/": "CS",
      "urn:ietf:params:xml:ns:caldav": "C"
    }, nest: () {
      out.element("response", namespace: "DAV:", nest: () {
        out.element("href", namespace: "DAV:", nest: path);

        out.element("propstat", namespace: "DAV:", nest: () {
          out.element("prop", namespace: "DAV:", nest: () {
            out.element("resourcetype", namespace: "DAV:", nest: () {
              out.element("collection", namespace: "DAV:");
            });
          });

          out.element("status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
        });
      });

      for (ICalendarLocalSchedule schedule in (link.provider as SimpleNodeProvider).nodes.values.where((x) => x is ICalendarLocalSchedule)) {
        Uri syncTokenUri = request.requestedUri;
        syncTokenUri = syncTokenUri
          .replace(path: pathlib.join(syncTokenUri.path, "sync") + "/${generateToken()}");
        for (XML.XmlElement e in prop.children.where((x) => x is XML.XmlElement)) {
          var name = e.name.local;

          if (name == "displayname") {
            results[e.name] = schedule.displayName;
          } else if (name == "getctag" || name == "getetag") {
            results[e.name] = schedule.calculateTag();
          } else if (name == "principal-URL" && false) {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", namespace: "DAV:", nest: "/");
            };
          } else if (name == "getcontenttype") {
            results[e.name] = (XML.XmlBuilder out) {
              out.text("text/calendar; component=vevent");
            };
          } else if (name == "calendar-home-set") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", namespace: "DAV:", nest: pathlib.join(pathlib.dirname(path), pathlib.basename(path) + "/"));
            };
          } else if (name == "current-user-principal" && false) {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", namespace: "DAV:", nest: "/principals/main/");
            };
          } else if (name == "calendar-user-address-set") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", namespace: "DAV:", nest: "/principals/main/");
            };
          } else if (name == "supported-report-set") {
            results[e.name] = (XML.XmlBuilder out) {
              for (var name in const ["calendar-query"]) {
                out.element("supported-report", namespace: "urn:ietf:params:xml:ns:caldav", nest: () {
                  out.element("report", namespace: "urn:ietf:params:xml:ns:caldav", nest: name);
                });
              }
            };
          } else if (name == "calendar-collection-set") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", nest: schedule.displayName);
            };
          } else if (name == "principal-collection-set") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", namespace: "DAV:", nest: "/");
            };
          } else if (name == "supported-calendar-component-set") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("comp", namespace: "urn:ietf:params:xml:ns:caldav", attributes: {
                "name": "VEVENT"
              });
            };
          } else if (name == "sync-token") {
            results[e.name] = (XML.XmlBuilder out) {
              out.text(syncTokenUri.toString());
            };
          } else if (name == "resourcetype") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("calendar", namespace: "urn:ietf:params:xml:ns:caldav");
            };
          } else if (name == "sync-level") {
            results[e.name] = "1";
          } else if (name == "owner" || name == "source") {
            results[e.name] = (XML.XmlBuilder out) {
              out.element("href", namespace: "DAV:", nest: path);
            };
          } else if (name == "calendar-description") {
            results[e.name] = schedule.displayName;
          } else if (name == "calendar-color") {
            results[e.name] = "FF5800";
          }
        }

        out.element("response", namespace: "DAV:", nest: () {
          out.element("href", namespace: "DAV:", nest: "/calendars/${schedule.displayName}/");
          out.element("propstat", namespace: "DAV:", nest: () {
            out.element("prop", namespace: "DAV:", nest: () {
              for (XML.XmlName key in results.keys) {
                String ns = "DAV:";
                if (key.local == "getctag") {
                  ns = "http://calendarserver.org/ns/";
                }

                if (key.local == "supported-calendar-component-set") {
                  ns = "urn:ietf:params:xml:ns:caldav";
                }

                out.element(key.local, namespace: ns, nest: () {

                  if (results[key] is String || results[key] is num) {
                    out.text(results[key]);
                  } else if (results[key] is Function) {
                    results[key](out);
                  }
                });
              }
            });


            out.element("status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
          });
        });
      }
    });

    await end(out.build().toXmlString(pretty: true), status: 207);
    return;
  } else if (path.startsWith("/calendars/") && (method == "PROPPATCH")) {
    var input = await request
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())
      .join("\n");
    response.headers.contentType =
      ContentType.parse("application/xml; charset=utf-8");
    await end("""
<?xml version='1.0' encoding='UTF-8'?>
<multistatus xmlns='DAV:'>
  <response>
    <href>${path}</href>
    <propstat>
      <prop>
      </prop>
      <status>HTTP/1.1 403 Forbidden</status>
    </propstat>
  </response>
</multistatus>
    """, status: 207);
    return;
  } else if (path.startsWith("/calendars/") && path != "/calendars/" && method == "REPORT") {
    var input = await request
      .transform(const Utf8Decoder())
      .transform(const LineSplitter())
      .join("\n");

    logger.fine(input);

    var name = parts[2];
    ICalendarLocalSchedule sched = findLocalSchedule(name);

    var out = new XML.XmlBuilder();
    out.element("multistatus", namespaces: {
      "DAV:": "",
      "urn:ietf:params:xml:ns:caldav": "c",
    }, namespace: "DAV:", nest: () {
      out.element("response", namespace: "DAV:", nest: () {
        out.element("href", namespace: "DAV:", nest: "/calendars/${name}.ics");
        out.element("propstat", namespace: "DAV:", nest: () {
          out.element("prop", nest: () {
            out.element("getcontenttype", namespace: "DAV:", nest: "text/calendar; component=vevent");
            out.element("getetag", namespace: "DAV:", nest: sched.calculateTag());

            if (input.contains("calendar-data")) {
              out.element("calendar-data", namespace: "urn:ietf:params:xml:ns:caldav", nest: sched.generatedCalendar);
            }
          });

          out.element("status", namespace: "DAV:", nest: "HTTP/1.1 200 OK");
        });
      });
    });

    await end("""
<?xml version="1.0" encoding="UTF-8"?>
${out.build().toXmlString()}
    """, status: 207);
    return;
  }

  if (method == "OPTIONS") {
    await end("Ok.");
    return;
  }

  await sendNotFound();
}
