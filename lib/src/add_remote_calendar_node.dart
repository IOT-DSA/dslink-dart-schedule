import 'package:dslink/dslink.dart';

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

  AddRemoteCalendarNode(String path) : super(path);

  @override
  dynamic onInvoke(Map<String, dynamic> params) async {
    final result = <String, dynamic>{_success: false, _message: ''};

  }
}
