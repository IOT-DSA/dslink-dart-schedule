import 'dart:async' show Future;

import 'package:dslink/dslink.dart';
import 'package:dslink/nodes.dart' show NodeNamer;

import 'common.dart';

class DataRootNode extends SimpleNode {
  static const String pathName = 'data';
  static const String isType = 'schedule/data/root';

  static Map<String, dynamic> def() => {
    r'$is': isType
  };

  DataRootNode(String path) : super(path);

  @override
  void onCreated() {
    provider.addNode('$path/${DataAddNode.pathName}', DataAddNode.def());
    provider.addNode('$path/${DataAddValue.pathName}', DataAddValue.def());
  }
}

class DataNode extends SimpleNode {
  static const String isType = 'schedule/data/node';

  static Map<String, dynamic> def([String nType, dynamic value]) {
    var m = {
      r'$is': isType,
      r'$writable': 'write',
    };

    if (nType != null) {
      m[r'$type'] = nType;
      m[r'?value'] = value;
    } else {
      m[r'$type'] = 'dynamic';
    }

    return m;
  }

  final LinkProvider _link;
  DataNode(String path, this._link) : super(path);

  @override
  void onCreated() {
    provider.addNode('$path/${DataAddNode.pathName}', DataAddNode.def());
    provider.addNode('$path/${DataAddValue.pathName}', DataAddValue.def());
    provider.addNode('$path/${DataRemove.pathName}', DataRemove.def());
  }

  @override
  bool onSetValue(Object value) {
    new Future.delayed(const Duration(milliseconds: 500), () => _link.save());
    return false;
  }
}

class DataAddNode extends SimpleNode {
  static const String pathName = 'add_node';
  static const String isType = 'schedule/data/addNode';

  static const String _name = 'Name';

  static Map<String,dynamic> def() => {
    r'$is': isType,
    r'$name': 'Add Node',
    r'$actionGroup': 'Add',
    r'$actionGroupSubTitle': 'Node',
    r'$invokable': 'write',
    r'$params': [ {'name': _name, 'type': 'string', 'placeholder': 'Node name'}]
  };

  final LinkProvider _link;
  DataAddNode(String path, this._link) : super(path) {
    serializable = false;
  }

  @override
  void onInvoke(Map<String,dynamic> params) {
    var name = params[_name];
    var encName = NodeNamer.createName(name);

    var p = '${parent.path}/$encName';
    var nd = provider.getNode(p);
    if (nd != null) {
      throw new ArgumentError.value(name, _name, 'A node with that name already exists');
    }

    provider.addNode(p, DataNode.def());
    _link.save();
  }
}

class DataAddValue extends SimpleNode {
  static const String pathName = 'add_value';
  static const String isType = 'schedule/data/addValue';

  static const String _name = 'Name';
  static const String _value = 'Value';
  static const String _type = 'Type';

  static const List<String> _valueTypes =
      const <String>['string', 'number', 'bool', 'array', 'map', 'dynamic'];

  static Map<String,dynamic> def() => {
      r'$is': isType,
      r'$name': 'Add Value',
      r'$actionGroup': 'Add',
      r'$actionGroupSubTitle': 'Value',
      r'$invokable': 'write',
      r'$params': [
        {'name': _name, 'type': 'string', 'placeholder': 'Value name'},
        {'name': _value, 'type': 'dynamic', 'placeholder': 'Value'},
        {'name': _type, 'type': 'enum[${_valueTypes.join(',')}]', 'default': 'string'}
      ]
  };

  final LinkProvider _link;
  DataAddValue(String path, this._link) : super(path) { serializable = false; }

  @override
  void onInvoke(Map<String, dynamic> params) {
    var name = params[_name] as String;
    var encName = NodeNamer.createName(name);

    var p = '${parent.path}/$encName';

    var nd = provider.getNode(p);
    if (nd != null) {
      throw new ArgumentError.value(name, _name, 'A node with that name already exists');
    }

    var ty = params[_type] as String;
    var value = params[_value];

    switch (_valueTypes.indexOf(ty)) {
      case 0: // String
        print('Adding string $p');
        provider.addNode(p, DataNode.def(ty, _asString(value)));
        break;
      case 1: // Number
        provider.addNode(p, DataNode.def(ty, _asNum(value)));
        break;
      case 2: // bool
        provider.addNode(p, DataNode.def(ty, _asBool(value)));
        break;
      case 3: // array
      case 4: // map
      case 5: // dynamic
        provider.addNode(p, DataNode.def(ty, value));
        break;
      default: // Not found, invalid type
        throw new ArgumentError.value(ty, _type, 'Unknown value type');
    }

    _link.save();
  }

  String _asString(Object value) {
    if (value is String) return value;
    return value.toString();
  }

  num _asNum(Object value) {
    if (value is num) return value;
    return num.parse(value);
  }

  bool _asBool(Object value) {
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase().trim() == 'true';
    }

    throw new ArgumentError.value(value, _value, 'Value is not a boolean');
  }
}

class DataRemove extends SimpleNode {
  static const String pathName = 'remove';
  static const String isType = 'schedule/data/remove';

  static Map<String, dynamic> def() => {
    r'$is': isType,
    r'$name': 'Remove',
    r'$invokable': 'write',
  };

  final LinkProvider _link;
  DataRemove(String path, this._link) : super(path) {
    serializable = false;
  }

  @override
  void onInvoke(Map<String, dynamic> _) {
    RemoveNode(provider, parent);
    _link.save();
  }
}