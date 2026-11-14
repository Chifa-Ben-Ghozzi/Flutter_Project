import 'dart:async';
import 'package:flutter/foundation.dart';
import '../repositories/chat_repository.dart';
import 'auth_provider.dart';

/// Nombre de messages non lus (Provider), en temps réel : badge de l'icône messagerie.
/// Les nouveaux messages arrivent en push grâce au serveur push (app fermée ou en arrière-plan).
class ChatProvider extends ChangeNotifier {
  final AuthProvider auth;
  ChatProvider(this.auth);

  int _unread = 0;
  int get unread => _unread;

  StreamSubscription? _sub;
  bool _wasLoggedIn = false;

  void init() {
    auth.addListener(_onAuthChange);
    _onAuthChange();
  }

  void _onAuthChange() {
    if (auth.loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = auth.loggedIn;
    _sub?.cancel();
    if (auth.loggedIn) {
      _sub = ChatRepository.unreadQuery().snapshots().listen((s) {
        _set(s.docs.length);
      }, onError: (_) {});
    } else {
      _set(0);
    }
  }

  void _set(int n) {
    if (n == _unread) return;
    _unread = n;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    auth.removeListener(_onAuthChange);
    super.dispose();
  }
}
