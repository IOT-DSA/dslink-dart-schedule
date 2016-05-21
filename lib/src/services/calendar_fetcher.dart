import 'package:http/http.dart';
import 'dart:async';
import '../calendar.dart';
import 'dart:convert';
import 'calendar_parser.dart';

class CalendarFetcher {
  Client _client;
  CalendarParser _calendarParser;

  CalendarFetcher(this._calendarParser);

  Future<Calendar> fetchRemoteCalendar(String url) async {
    _client = new Client();

    try {
      final response = await _client.get(url);

      if (response.statusCode > 200) {
        throw new Exception('Cannot fetch the remote calendar at $url');
      }

      final decodedResponse = response.body;

      _calendarParser.parse(decodedResponse);
    } catch (e) {
      rethrow;
    } finally {
      _client.close();
    }
  }
}
