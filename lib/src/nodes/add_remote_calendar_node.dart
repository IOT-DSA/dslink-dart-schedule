import 'package:dslink/dslink.dart';
import 'package:dslink_schedule/services.dart';
import 'package:di/di.dart';

class AddRemoteCalendarNode extends SimpleNode {
  static const String isType = 'addRemoteCalendarNode';
  static const String pathName = 'addRemoteCalendar';

  static const String _name = 'Calendar name';
  static const String _url = 'Calendar URL';
  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> definition() => <String, dynamic>{
        r'$is': isType,
        r'$name': 'Add remote calendar',
        r'$invokable': 'write',
        r'$params': [
          {'name': _name, 'type': 'string', 'placeholder': 'Site Name'},
          {
            'name': _url,
            'type': 'string',
            'placeholder': 'http://www.somesite.com/mycal.ics'
          },
        ],
        r'$columns': [
          {'name': _success, 'type': 'bool', 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ]
      };

  CalendarFetcher _calendarFetcher;

  AddRemoteCalendarNode(String path, ModuleInjector injector) : super(path) {
    _calendarFetcher = injector.get(CalendarFetcher);
  }

  @override
  dynamic onInvoke(Map<String, dynamic> params) async {
    final result = <String, dynamic>{_success: false, _message: ''};

    final calendarName = params[_name] as String;
    final calendarUrl = params[_url] as String;

    final calendar = await _calendarFetcher.fetchRemoteCalendar(calendarUrl);
    var bob = 12;
  }
}
