import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../api.dart';
import '../models.dart';

/// Session de l'utilisateur (Provider) avec Firebase Authentication :
/// connexion, inscription, déconnexion et profil.
/// Les écrans lisent l'utilisateur avec `context.watch<AuthProvider>().user`.
class AuthProvider extends ChangeNotifier {
  FirebaseAuth? _auth;
  FirebaseAuth get auth => _auth ??= FirebaseAuth.instance;

  AuthProvider({FirebaseAuth? auth}) : _auth = auth;

  AppUser? _user;
  AppUser? get user => _user;
  bool get loggedIn => _user != null;

  /// Appelé juste avant la déconnexion (ex: retirer le jeton de notification de cet appareil).
  Future<void> Function()? beforeLogout;

  /// Email universitaire : domaine contenant "univ", ou finissant par .edu / .ac.xx
  /// (la même règle est vérifiée par les règles de sécurité Firestore).
  static bool isUniEmail(String e) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) &&
      RegExp(r'(^|\.)(edu|ac)(\.|$)|univ', caseSensitive: false).hasMatch(e.split('@')[1]);

  /// Au démarrage : Firebase garde la session sur l'appareil, on recharge le profil.
  Future<void> init() async {
    final current = await auth.authStateChanges().first;
    if (current == null) return;
    Api.uid = current.uid;
    try {
      _user = await Api.me(); // fonctionne aussi hors ligne grâce au cache Firestore
      notifyListeners();
    } catch (_) {
      // Profil introuvable : on repart de l'écran de connexion
      Api.uid = null;
    }
  }

  Future<void> login(String email, String password) => _wrap(() async {
        final cred = await auth.signInWithEmailAndPassword(email: email.trim(), password: password);
        Api.uid = cred.user!.uid;
        _user = await Api.me();
        notifyListeners();
      });

  Future<void> register(String email, String password, String name) => _wrap(() async {
        if (!isUniEmail(email)) throw ApiException('Utilisez votre email universitaire');
        final cred = await auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        await cred.user!.updateDisplayName(name);
        Api.uid = cred.user!.uid;
        _user = await Api.createProfile(email.trim(), name);
        notifyListeners();
      });

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } catch (_) {}
    await auth.signOut();
    Api.uid = null;
    _user = null;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> body) async {
    _user = await Api.updateProfile(body);
    notifyListeners();
  }

  /// Recharge la note / le nombre d'avis après un nouvel avis.
  Future<void> refresh() async {
    try {
      _user = await Api.me();
      notifyListeners();
    } catch (_) {}
  }

  /// Pour les tests : simule un utilisateur connecté sans Firebase Auth.
  @visibleForTesting
  void debugSignIn(AppUser user) {
    Api.uid = user.id;
    _user = user;
    notifyListeners();
  }

  /// Traduit les erreurs Firebase Auth en messages déjà traduits par L10n.trServer.
  Future<void> _wrap(Future<void> Function() f) async {
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      throw switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-login-credentials' =>
          ApiException('Email ou mot de passe incorrect'),
        'email-already-in-use' => ApiException('Email déjà utilisé'),
        'weak-password' => ApiException('Mot de passe : 6 caractères minimum'),
        'invalid-email' => ApiException("Format d'email invalide"),
        'too-many-requests' => ApiException('Trop de tentatives, réessayez plus tard'),
        'network-request-failed' => NetworkException(),
        _ => ApiException(e.message ?? e.code),
      };
    }
  }
}
