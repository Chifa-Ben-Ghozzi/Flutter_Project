import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/firestore_service.dart';
import 'mappers.dart';

/// Notifications : création (lors d'une réservation, d'un avis…), lecture et "tout marquer comme lu".
class NotificationRepository {
  static CollectionReference<Map<String, dynamic>> get _notifs => FirestoreService.notifications;

  /// Requête des notifications de l'utilisateur connecté (écoutée en temps réel par NotificationsProvider).
  static Query<Map<String, dynamic>> myQuery() => _notifs.where('userId', isEqualTo: FirestoreService.currentUid);

  static AppNotification fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final n = d.data()!;
    return AppNotification.fromJson({
      ...n,
      'id': d.id,
      // Juste après la création, l'heure du serveur n'est pas encore connue
      'createdAt': n['createdAt'] == null ? DateTime.now().toUtc().toIso8601String() : Mappers.iso(n['createdAt']),
    });
  }

  /// Les 50 dernières notifications, de la plus récente à la plus ancienne.
  static Future<List<AppNotification>> list() => FirestoreService.run(() async {
        final list = (await myQuery().get()).docs.map(fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(50).toList();
      });

  static Future<void> markAllRead() => FirestoreService.run(() async {
        final unread = (await myQuery().where('read', isEqualTo: false).get()).docs;
        if (unread.isEmpty) return;
        final batch = FirestoreService.db.batch();
        for (final d in unread) {
          batch.update(d.reference, {'read': true});
        }
        await batch.commit();
      });

  /// Ajoute une notification pour [userId] dans un batch ou une transaction (même envoi que l'action).
  /// `data` permet à l'app et au serveur push d'écrire le texte dans la langue de chacun.
  static void add(dynamic writer, String userId, String type, Map<String, dynamic> ride, String rideId,
      Map<String, dynamic> extra) {
    final doc = {
      'userId': userId,
      'type': type,
      'rideId': rideId,
      'data': {'from': ride['from'], 'to': ride['to'], 'date': ride['date'], 'time': ride['time'], ...extra},
      'read': false,
      'pushed': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final ref = _notifs.doc();
    if (writer is WriteBatch) {
      writer.set(ref, doc);
    } else {
      (writer as Transaction).set(ref, doc);
    }
  }
}
