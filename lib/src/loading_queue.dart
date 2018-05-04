import 'dart:async' show Future;

class LoadingQueue {
  List<Future> _queue = <Future>[];

  Iterable<Future> get queue {
    if (_queue == null) return null;
    return _queue;
  }

  void add(Future f) {
    if (_queue == null) return;
    _queue.add(f);
  }

  void clear() {
    _queue = null;
  }
}