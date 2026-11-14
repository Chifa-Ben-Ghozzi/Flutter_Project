import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/exceptions.dart';
import '../services/firestore_service.dart';

/// Alertes de trajet (recherches enregistrées).
/// Quand un conducteur publie un trajet, RideRepository.publish prévient chaque utilisateur
/// dont une alerte correspond (notification `ride_alert`, puis push par le serveur).
class AlertRepository {
  static CollectionReference<Map<String, dynamic>> get _alerts => FirestoreService.alerts;

  /// Nombre maximum d'alertes par utilisateur.
  static const maxAlerts = 10;

  static RideAlert _fromDoc(DocumentSnapshot<Map<String, dynamic>> d) => RideAlert.fromJson({...?d.data(), 'id': d.id});

  /// Mes alertes, les plus récentes en premier.
  static Future<List<RideAlert>> mine() => FirestoreService.run(() async {
        final docs = (await _alerts.where('userId', isEqualTo: FirestoreService.currentUid).get()).docs.toList()
          ..sort((a, b) {
            final ta = a.data()['createdAt'], tb = b.data()['createdAt'];
            return (tb is Timestamp ? tb.millisecondsSinceEpoch : 0)
                .compareTo(ta is Timestamp ? ta.millisecondsSinceEpoch : 0);
          });
        return docs.map(_fromDoc).toList();
      });

  /// Crée une alerte. Au moins un lieu (départ ou destination) est obligatoire.
  static Future<void> add({String from = '', String to = '', double? maxPrice}) => FirestoreService.run(() async {
        final f = from.trim(), t = to.trim();
        if (f.isEmpty && t.isEmpty) throw ApiException('Indiquez un départ ou une destination');
        final existing = await mine();
        if (existing.length >= maxAlerts) throw ApiException('Maximum $maxAlerts alertes');
        final same = existing.any((a) =>
            a.from.toLowerCase() == f.toLowerCase() && a.to.toLowerCase() == t.toLowerCase() && a.maxPrice == maxPrice);
        if (same) throw ApiException('Cette alerte existe déjà');
        await _alerts.add({
          'userId': FirestoreService.currentUid,
          'from': f,
          'to': t,
          'maxPrice': maxPrice,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

  static Future<void> delete(String id) => FirestoreService.run(() => _alerts.doc(id).delete());

  /// Utilisateurs (autres que moi) dont au moins une alerte correspond au trajet ; un seul envoi par personne.
  static Future<Set<String>> matchingUsers(Ride ride) async {
    final me = FirestoreService.currentUid;
    return (await _alerts.get())
        .docs
        .map(_fromDoc)
        .where((a) => a.userId != me && a.matches(ride))
        .map((a) => a.userId)
        .toSet();
  }
}
