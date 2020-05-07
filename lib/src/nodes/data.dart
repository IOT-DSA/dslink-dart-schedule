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
    provider.addNode('$path/${DataPublish.pathName}', DataPublish.def());
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

class DataPublish extends SimpleNode {
  static const String pathName = 'publish';
  static const String isType = 'schedule/data/publish';

  static const String _path = 'Path';
  static const String _value = 'Value';
  static const String _type = 'Type';
  static const String _force = 'Force';

  static const List<String> _valueTypes =
  const <String>['string', 'number', 'bool', 'array', 'map', 'dynamic'];

  static Map<String, dynamic> def() => {
      r'$is': isType,
      r'$name': 'Publish Value',
      r'$invokable': 'write',
      r'$params': [
        { 'name': _path, 'type': 'string', 'placeholder': '/data/path/to/value'},
        {'name': _value, 'type': 'dynamic', 'placeholder': 'Value'},
        {'name': _type, 'type': 'enum[${_valueTypes.join(',')}]', 'default': 'string'},
        {
          'name': _force,
          'type': 'bool',
          'default': false,
          'description': 'Force the published value, even if the node exists ' +
                          'and there is a type mismatch.'
        }
      ],
  };

  final LinkProvider _link;
  DataPublish(String path, this._link) : super(path) { serializable = false; }

  @override
  void onInvoke(Map<String, dynamic> params) {
    var pPath = params[_path] as String;
    var force = (params[_force] as bool) ?? false;
    var ty = params[_type] as String;
    var value = params[_value];

    if (pPath == null || pPath.isEmpty || !pPath.startsWith('/data/')) {
      throw new ArgumentError.value(path, _path,
          'Path must be specified and begin with "/data/"');
    }

    var pp = new Path(pPath.substring('/data/'.length));
    var newNode = provider.getNode('${parent.path}/${pp.path}') as DataNode;
    if (newNode != null) { // Already exists
      if (newNode.configs[r'$type'] != ty) { // But different types
        if (!force) { // And not forced, so error.
          throw new ArgumentError.value(ty, _type,
              'type mismatch. Cannot update value');
        }

        // Force value by first updating the type, then the value
        newNode.configs[r'$type'] = ty;
        newNode.updateList(r'$type');
      }
      // Value exists, type matches. Update value
      newNode.updateValue(value);
      return;
    }

    _createPath(pp.parent);
    var p = '${parent.path}/${pp.path}';

    switch (_valueTypes.indexOf(ty)) {
      case 0: // String
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

  /// walk the node path and create the tree as appropriate
  void _createPath(Path pth) {
    if (pth.parentPath.isNotEmpty) _createPath(pth.parent);

    // parent is [DataRootNode].
    var rootPath = parent.path;
    var newPath = '$rootPath/${pth.path}';
    var nd = provider.getNode(newPath);
    if (nd == null) {
      provider.addNode(newPath, DataNode.def());
    }
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
  DataRemove(String path, this._link) : super(path) { serializable = false; }

  @override
  void onInvoke(Map<String, dynamic> _) {
    RemoveNode(provider, parent);
    _link.save();
  }
}