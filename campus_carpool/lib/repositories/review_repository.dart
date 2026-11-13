import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/exceptions.dart';
import '../services/firestore_service.dart';
import 'mappers.dart';
import 'notification_repository.dart';
import 'user_repository.dart';

/// Avis : un passager et son conducteur se notent après un trajet partagé.
class ReviewRepository {
  static CollectionReference<Map<String, dynamic>> get _reviews => FirestoreService.reviews;

  /// Note une personne après un trajet partagé (un seul avis par personne et par trajet).
  static Future<void> add(String rideId, String toId, int stars, String comment) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        if (stars < 1 || stars > 5) throw ApiException('Note entre 1 et 5');
        final r = (await FirestoreService.rides.doc(rideId).get()).data();
        if (r == null) throw ApiException('Trajet introuvable');
        if (r['status'] == 'cancelled' || (r['status'] != 'completed' && Mappers.rideDate(r).isAfter(DateTime.now()))) {
          throw ApiException('Vous pourrez noter après le trajet');
        }
        // La réservation acceptée qui relie les deux personnes (vérifiée aussi par les règles)
        final passenger = r['driverId'] == me ? toId : me;
        final link = (await FirestoreService.bookings
                .where('rideId', isEqualTo: rideId)
                .where('passengerId', isEqualTo: passenger)
                .get())
            .docs
            .where((d) => d.data()['status'] == 'accepted')
            .firstOrNull;
        final allowed = link != null && (r['driverId'] == me || r['driverId'] == toId) && toId != me;
        if (!allowed) throw ApiException('Vous ne pouvez pas noter cette personne pour ce trajet');
        final reviewId = '${rideId}_${me}_$toId';
        if ((await _reviews.doc(reviewId).get()).exists) throw ApiException('Avis déjà envoyé');
        final myName = await UserRepository.myName();
        final batch = FirestoreService.db.batch();
        batch.set(_reviews.doc(reviewId), {
          'rideId': rideId,
          'bookingId': link.id,
          'fromId': me,
          'fromName': myName,
          'toId': toId,
          'stars': stars,
          'comment': comment.length > 300 ? comment.substring(0, 300) : comment,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.update(FirestoreService.users.doc(toId), {
          'ratingSum': FieldValue.increment(stars),
          'ratingCount': FieldValue.increment(1),
          'lastReview': reviewId,
        });
        NotificationRepository.add(batch, toId, 'review', r, rideId, {'name': myName, 'stars': stars});
        await batch.commit();
      });

  /// Les personnes que [fromId] a déjà notées pour ce trajet.
  static Future<Set<String>> alreadyRatedBy(String rideId, String fromId) async =>
      (await _reviews.where('rideId', isEqualTo: rideId).where('fromId', isEqualTo: fromId).get())
          .docs
          .map((d) => d.data()['toId'] as String)
          .toSet();
}
