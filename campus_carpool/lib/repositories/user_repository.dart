import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/exceptions.dart';
import '../services/firestore_service.dart';
import 'mappers.dart';

/// Utilisateurs : profil connecté, profil public avec avis, mise à jour.
class UserRepository {
  static CollectionReference<Map<String, dynamic>> get _users => FirestoreService.users;

  /// Profil de l'utilisateur connecté (fonctionne aussi hors ligne grâce au cache Firestore).
  static Future<AppUser> me() => FirestoreService.run(() async {
        final d = await _users.doc(FirestoreService.currentUid).get();
        if (!d.exists) throw ApiException('Utilisateur introuvable');
        return AppUser.fromJson(Mappers.user(d, full: true));
      });

  /// Crée le profil Firestore juste après l'inscription Firebase Auth.
  static Future<AppUser> createProfile(String email, String name) => FirestoreService.run(() async {
        await _users.doc(FirestoreService.currentUid).set({
          'email': email.toLowerCase(),
          'name': name,
          'phone': '',
          'carModel': '',
          'carPlate': '',
          'photo': null,
          'ratingSum': 0,
          'ratingCount': 0,
          'fcmTokens': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        });
        return me();
      });

  static Future<AppUser> updateProfile(Map<String, dynamic> body) => FirestoreService.run(() async {
        final car = body['car'] as Map?;
        await _users.doc(FirestoreService.currentUid).update({
          if (body['name'] != null) 'name': body['name'],
          if (body.containsKey('phone')) 'phone': body['phone'],
          if (car != null) 'carModel': car['model'] ?? '',
          if (car != null) 'carPlate': car['plate'] ?? '',
          if (body.containsKey('photo')) 'photo': body['photo'],
        });
        return me();
      });

  /// Modifie un champ du profil connecté (jetons de notification, langue…).
  static Future<void> setField(String field, Object value) =>
      FirestoreService.run(() => _users.doc(FirestoreService.currentUid).update({field: value}));

  /// Profil public d'un utilisateur avec ses 20 derniers avis.
  static Future<AppUser> publicUser(String id) => FirestoreService.run(() async {
        final d = await _users.doc(id).get();
        if (!d.exists) throw ApiException('Utilisateur introuvable');
        final reviews = (await FirestoreService.reviews.where('toId', isEqualTo: id).get()).docs.map((r) {
          final v = r.data();
          return {...v, 'id': r.id, 'from': v['fromName'] ?? '', 'createdAt': Mappers.iso(v['createdAt'])};
        }).toList()
          ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
        return AppUser.fromJson({...Mappers.user(d), 'reviews': reviews.take(20).toList()});
      });

  /// Profils publics (sans photo, pour les listes), lus en parallèle ; clé = uid.
  static Future<Map<String, Map<String, dynamic>>> byIds(Iterable<String> ids) async {
    final unique = ids.toSet().where((id) => id.isNotEmpty).toList();
    final docs = await Future.wait(unique.map((id) => _users.doc(id).get()));
    return {
      for (final d in docs)
        if (d.exists) d.id: (Mappers.user(d)..remove('photo')),
    };
  }

  /// Profil public complet (avec photo) d'un utilisateur, ou null s'il n'existe pas.
  static Future<Map<String, dynamic>?> byId(String id) async {
    final d = await _users.doc(id).get();
    return d.exists ? Mappers.user(d) : null;
  }

  /// Nom de l'utilisateur connecté (pour le texte des notifications).
  static Future<String> myName() async =>
      ((await _users.doc(FirestoreService.currentUid).get()).data()?['name'] as String?) ?? '';
}
