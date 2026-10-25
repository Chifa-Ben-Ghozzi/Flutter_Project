import 'package:flutter/foundation.dart';
import '../api.dart';
import '../models.dart';

/// Session de l'utilisateur (Provider) : qui est connecté, connexion, inscription, profil.
/// Les écrans lisent l'utilisateur avec `context.watch<AuthProvider>().user`
/// et sont redessinés automatiquement quand il change.
class AuthProvider extends ChangeNotifier {
  AppUser? _user;
  AppUser? get user => _user;
  bool get loggedIn => _user != null;

  AuthProvider() {
    Api.onUnauthorized = logout; // token expiré -> retour à l'écran de connexion
  }

  /// Au démarrage : reprend la session enregistrée sur le téléphone.
  Future<void> init() async {
    await Api.loadToken();
    if (Api.token == null) return;
    try {
      _user = await Api.me(); // fonctionne aussi hors ligne grâce au cache
      notifyListeners();
    } on ApiException {
      await Api.saveToken(null); // token refusé par le serveur
    } catch (_) {
      // Serveur injoignable et pas de cache : on reste déconnecté
    }
  }

  Future<void> login(String email, String password) async {
    final (token, user) = await Api.login(email, password);
    await _start(token, user);
  }

  Future<void> register(String email, String password, String name) async {
    final (token, user) = await Api.register(email, password, name);
    await _start(token, user);
  }

  Future<void> _start(String token, AppUser user) async {
    await Api.saveToken(token);
    _user = user;
    notifyListeners();
  }

  Future<void> logout() async {
    await Api.saveToken(null);
    _user = null;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> body) async {
    _user = await Api.updateProfile(body);
    notifyListeners();
  }

  /// Recharge note / nombre d'avis après un nouvel avis.
  Future<void> refresh() async {
    try {
      _user = await Api.me();
      notifyListeners();
    } catch (_) {}
  }
}
