import 'package:firebase_auth/firebase_auth.dart';
import 'exceptions.dart';

/// Accès technique à Firebase Authentication : connexion, inscription, déconnexion.
/// Les erreurs Firebase sont traduites en ApiException / NetworkException.
class AuthService {
  FirebaseAuth? _auth;
  FirebaseAuth get _firebase => _auth ??= FirebaseAuth.instance;

  /// [auth] remplaçable dans les tests ; sinon l'instance Firebase, créée à la première utilisation.
  AuthService({FirebaseAuth? auth}) : _auth = auth;

  /// Email universitaire : domaine contenant "univ", ou finissant par .edu / .ac.xx
  /// (la même règle est vérifiée par les règles de sécurité Firestore).
  static bool isUniEmail(String e) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) &&
      RegExp(r'(^|\.)(edu|ac)(\.|$)|univ', caseSensitive: false).hasMatch(e.split('@')[1]);

  /// Session gardée par Firebase sur l'appareil (null si personne n'est connecté).
  Future<String?> currentUserId() async => (await _firebase.authStateChanges().first)?.uid;

  /// Connexion ; renvoie l'uid.
  Future<String> signIn(String email, String password) => _wrap(() async {
        final cred = await _firebase.signInWithEmailAndPassword(email: email.trim(), password: password);
        return cred.user!.uid;
      });

  /// Inscription (email universitaire obligatoire) ; renvoie l'uid.
  Future<String> register(String email, String password, String name) => _wrap(() async {
        if (!isUniEmail(email)) throw ApiException('Utilisez votre email universitaire');
        final cred = await _firebase.createUserWithEmailAndPassword(email: email.trim(), password: password);
        await cred.user!.updateDisplayName(name);
        return cred.user!.uid;
      });

  Future<void> signOut() => _firebase.signOut();

  /// Traduit les erreurs Firebase Auth en messages déjà traduits par L10n.trServer.
  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on FirebaseAuthException catch (e) {
      throw switch (e.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-login-credentials' =>
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
