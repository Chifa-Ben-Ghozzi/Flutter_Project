import 'package:flutter/foundation.dart';
import '../models.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Session de l'utilisateur (Provider) : connexion, inscription, déconnexion et profil.
/// Les écrans lisent l'utilisateur avec `context.watch<AuthProvider>().user`.
///
/// Firebase Authentication est utilisé via [AuthService] ; le profil via [UserRepository].
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthProvider({AuthService? authService}) : _authService = authService ?? AuthService();

  AppUser? _user;
  AppUser? get user => _user;
  bool get loggedIn => _user != null;

  /// Appelé juste avant la déconnexion (ex: retirer le jeton de notification de cet appareil).
  Future<void> Function()? beforeLogout;

  /// Email universitaire (règle partagée avec l'écran de connexion et les règles Firestore).
  static bool isUniEmail(String e) => AuthService.isUniEmail(e);

  /// Au démarrage : Firebase garde la session sur l'appareil, on recharge le profil.
  Future<void> init() async {
    final uid = await _authService.currentUserId();
    if (uid == null) return;
    FirestoreService.uid = uid;
    try {
      _user = await UserRepository.me(); // fonctionne aussi hors ligne grâce au cache Firestore
      notifyListeners();
    } catch (_) {
      // Profil introuvable : on repart de l'écran de connexion
      FirestoreService.uid = null;
    }
  }

  Future<void> login(String email, String password) async {
    FirestoreService.uid = await _authService.signIn(email, password);
    _user = await UserRepository.me();
    notifyListeners();
  }

  Future<void> register(String email, String password, String name) async {
    FirestoreService.uid = await _authService.register(email, password, name);
    _user = await UserRepository.createProfile(email.trim(), name);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } catch (_) {}
    await _authService.signOut();
    FirestoreService.uid = null;
    _user = null;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> body) async {
    _user = await UserRepository.updateProfile(body);
    notifyListeners();
  }

  /// Recharge la note / le nombre d'avis après un nouvel avis.
  Future<void> refresh() async {
    try {
      _user = await UserRepository.me();
      notifyListeners();
    } catch (_) {}
  }

  /// Pour les tests : simule un utilisateur connecté sans Firebase Auth.
  @visibleForTesting
  void debugSignIn(AppUser user) {
    FirestoreService.uid = user.id;
    _user = user;
    notifyListeners();
  }
}
