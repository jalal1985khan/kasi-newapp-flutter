import 'dart:async';

class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _controller = StreamController<String>.broadcast();
  
  Stream<String> get stream => _controller.stream;
  
  void fire(String event) {
    _controller.add(event);
  }
}
