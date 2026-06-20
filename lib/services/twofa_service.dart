import 'dart:async';

class TwoFactorAuthService {
  final Completer<String?> _completer = Completer<String?>();

  Future<String?> requestTwoFactorCode(
    String connectionName,
    String host,
    String prompt,
  ) async {
    if (!_completer.isCompleted) {
      _completer.complete(null);
    }
    final newCompleter = Completer<String?>();
    return newCompleter.future;
  }

  void completeWithCode(String code) {
    if (!_completer.isCompleted) {
      _completer.complete(code);
    }
  }

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete(null);
    }
  }
}
