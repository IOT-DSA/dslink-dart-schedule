import 'package:http/http.dart';
import 'dart:async';
import 'calendar.dart';
import 'dart:convert';

class CalendarFetcher {
  Client _client;

  Future<Calendar> fetchRemoteCalendar(Uri uri) async {
    _client = new Client();


    final response = await _client.get(uri);

    if (response.statusCode > 200) {
      throw new Exception('Cannot fetch the remote calendar at $uri');
    }

    final decodedResponse = JSON.decode(response);

    print (decodedResponse);
  }
}