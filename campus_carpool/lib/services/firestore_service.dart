import 'package:cloud_firestore/cloud_firestore.dart';
import 'exceptions.dart';
import 'network_status.dart';

/// Accès technique à Cloud Firestore, partagé par tous les repositories :
/// instance de la base, utilisateur connecté, collections et traduction des erreurs.
///
/// Collections :
///   users/{uid}            profil, note (ratingSum / ratingCount), jetons de notification
///   rides/{id}             trajets
///   bookings/{id}          demandes de place
///   reviews/{ride_from_to} avis (un seul par personne et par trajet)
///   notifications/{id}     notifications de chaque utilisateur
///   messages/{id}          messagerie conducteur ↔ passager (une conversation par réservation)
///   alerts/{id}            alertes de trajet (recherches enregistrées)
class FirestoreService {
  /// Remplaçable dans les tests par FakeFirebaseFirestore.
  static FirebaseFirestore? _db;
  static FirebaseFirestore get db => _db ??= FirebaseFirestore.instance;
  static set db(FirebaseFirestore v) => _db = v;

  /// Utilisateur connecté (uid Firebase Auth), renseigné par AuthProvider.
  static String? uid;

  /// En ligne / hors ligne, mis à jour à chaque échange avec Firestore.
  static final network = NetworkStatus();

  /// L'uid de l'utilisateur connecté, ou une erreur s'il n'y en a pas.
  static String get currentUid {
    final u = uid;
    if (u == null) throw ApiException('Non authentifié');
    return u;
  }

  static CollectionReference<Map<String, dynamic>> get users => db.collection('users');
  static CollectionReference<Map<String, dynamic>> get rides => db.collection('rides');
  static CollectionReference<Map<String, dynamic>> get bookings => db.collection('bookings');
  static CollectionReference<Map<String, dynamic>> get reviews => db.collection('reviews');
  static CollectionReference<Map<String, dynamic>> get notifications => db.collection('notifications');
  static CollectionReference<Map<String, dynamic>> get messages => db.collection('messages');
  static CollectionReference<Map<String, dynamic>> get alerts => db.collection('alerts');

  /// Exécute une opération Firestore en traduisant les erreurs techniques en erreurs de l'app.
  static Future<T> run<T>(Future<T> Function() f) async {
    try {
      final r = await f();
      network.set(true);
      return r;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        network.set(false);
        throw NetworkException();
      }
      if (e.code == 'permission-denied') throw ApiException('Action non autorisée');
      if (e.code == 'not-found') throw ApiException('Introuvable');
      rethrow;
    }
  }
}
