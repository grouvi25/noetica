import 'dart:async';

class PremiumService {
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  static final _controller = StreamController<bool>.broadcast();
  static Stream<bool> get changes => _controller.stream;

  Future<void> load() async {
    _isPremium = false;
  }

  void dispose() {}
}
