import 'package:flutter/foundation.dart';

/// En ligne / hors ligne : affiché par la bannière de l'écran d'accueil.
class NetworkStatus extends ChangeNotifier {
  bool _online = true;
  bool get online => _online;

  void set(bool v) {
    if (v == _online) return;
    _online = v;
    notifyListeners();
  }
}
