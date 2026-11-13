import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/exceptions.dart';
import '../services/firestore_service.dart';
import 'mappers.dart';
import 'notification_repository.dart';
import 'user_repository.dart';

/// Réservations : demander une place, répondre (conducteur), annuler (passager), mes réservations.
class BookingRepository {
  static CollectionReference<Map<String, dynamic>> get _rides => FirestoreService.rides;
  static CollectionReference<Map<String, dynamic>> get _bookings => FirestoreService.bookings;

  /// Le passager demande une place ; le conducteur est prévenu.
  static Future<void> request(String rideId) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final rd = await _rides.doc(rideId).get();
        final r = rd.data();
        if (r == null || r['status'] != 'open') throw ApiException('Trajet indisponible');
        if (r['driverId'] == me) throw ApiException('Vous ne pouvez pas réserver votre propre trajet');
        if (Mappers.rideDate(r).isBefore(DateTime.now())) throw ApiException('Ce trajet est déjà passé');
        if ((r['seatsLeft'] as num) < 1) throw ApiException('Plus de places');
        final mine = await _bookings.where('rideId', isEqualTo: rideId).where('passengerId', isEqualTo: me).get();
        if (mine.docs.any((d) => d.data()['status'] == 'pending' || d.data()['status'] == 'accepted')) {
          throw ApiException('Vous avez déjà une demande pour ce trajet');
        }
        final myName = await UserRepository.myName();
        final batch = FirestoreService.db.batch();
        batch.set(_bookings.doc(), {
          'rideId': rideId,
          'passengerId': me,
          'driverId': r['driverId'],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        NotificationRepository.add(batch, r['driverId'], 'booking_new', r, rideId, {'name': myName});
        await batch.commit();
      });

  /// Mes réservations (passager) avec le trajet et son conducteur.
  static Future<List<Booking>> myBookings() => FirestoreService.run(() async {
        final bookings = (await _bookings.where('passengerId', isEqualTo: FirestoreService.currentUid).get())
            .docs
            .map(Mappers.booking)
            .toList();
        final rideDocs =
            await Future.wait(bookings.map((b) => b['rideId'] as String).toSet().map((id) => _rides.doc(id).get()));
        final rides = {
          for (final d in rideDocs)
            if (d.exists) d.id: Mappers.ride(d)
        };
        final drivers = await UserRepository.byIds(rides.values.map((r) => r['driverId'] as String));
        final list = bookings.where((b) => rides.containsKey(b['rideId'])).map((b) {
          final r = rides[b['rideId']]!;
          return Booking.fromJson({
            ...b,
            'ride': {...r, 'driver': drivers[r['driverId']]}
          });
        }).toList()
          ..sort((a, b) => b.ride!.dateTime.compareTo(a.ride!.dateTime));
        return list;
      });

  /// Le conducteur accepte (une place en moins) ou refuse une demande.
  static Future<void> respond(String bookingId, bool accept) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final myName = await UserRepository.myName();
        await FirestoreService.db.runTransaction((tx) async {
          final bRef = _bookings.doc(bookingId);
          final b = (await tx.get(bRef)).data();
          if (b == null || b['driverId'] != me) throw ApiException('Réservation introuvable');
          final rRef = _rides.doc(b['rideId']);
          final r = (await tx.get(rRef)).data()!;
          if (r['status'] != 'open') throw ApiException('Trajet indisponible');
          if (b['status'] != 'pending') throw ApiException('Demande déjà traitée');
          if (accept) {
            if ((r['seatsLeft'] as num) < 1) throw ApiException('Plus de places disponibles');
            tx.update(rRef, {'seatsLeft': FieldValue.increment(-1)});
            tx.update(bRef, {'status': 'accepted'});
          } else {
            tx.update(bRef, {'status': 'declined'});
          }
          NotificationRepository.add(
              tx, b['passengerId'], accept ? 'booking_accepted' : 'booking_declined', r, b['rideId'], {'name': myName});
        });
      });

  /// Le passager annule sa demande ; si elle était acceptée, la place est rendue au trajet.
  static Future<void> cancel(String bookingId) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final myName = await UserRepository.myName();
        await FirestoreService.db.runTransaction((tx) async {
          final bRef = _bookings.doc(bookingId);
          final b = (await tx.get(bRef)).data();
          if (b == null || b['passengerId'] != me || !(b['status'] == 'pending' || b['status'] == 'accepted')) {
            throw ApiException('Réservation introuvable');
          }
          final rRef = _rides.doc(b['rideId']);
          final r = (await tx.get(rRef)).data()!;
          if (r['status'] != 'open') throw ApiException('Trajet indisponible');
          if (b['status'] == 'accepted') {
            // lastBooking permet aux règles de vérifier que c'est bien une place rendue par ce passager
            tx.update(rRef, {'seatsLeft': FieldValue.increment(1), 'lastBooking': bookingId});
          }
          tx.update(bRef, {'status': 'cancelled'});
          NotificationRepository.add(tx, b['driverId'], 'booking_cancelled', r, b['rideId'], {'name': myName});
        });
      });
}
