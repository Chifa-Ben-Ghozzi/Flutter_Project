import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_data.dart';
import 'package:campus_carpool/repositories/booking_repository.dart';
import 'package:campus_carpool/repositories/notification_repository.dart';
import 'package:campus_carpool/repositories/review_repository.dart';
import 'package:campus_carpool/repositories/ride_repository.dart';
import 'package:campus_carpool/repositories/user_repository.dart';
import 'package:campus_carpool/services/exceptions.dart';
import 'package:campus_carpool/services/firestore_service.dart';

/// Logique métier de l'app sur une base Firestore en mémoire (FakeFirebaseFirestore).
void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = await fakeDb();
    FirestoreService.uid = 'demo';
  });

  Future<Object?> error(Future<void> Function() f) async {
    try {
      await f();
      return null;
    } catch (e) {
      return e;
    }
  }

  group('Recherche et publication', () {
    test('la recherche montre les trajets à venir des autres, avec la note du conducteur', () async {
      final rides = await RideRepository.search({});
      expect(rides.map((r) => r.id), ['future']); // pas le trajet passé
      expect(rides.first.driver!.name, 'Amira');
      expect(rides.first.driver!.rating, 4.5); // 9 / 2
      expect(rides.first.myBookingStatus, isNull);
    });

    test('filtres : départ, destination, prix max, places min', () async {
      expect(await RideRepository.search({'from': 'aria'}), hasLength(1));
      expect(await RideRepository.search({'from': 'Tunis'}), isEmpty);
      expect(await RideRepository.search({'destination': 'esprit'}), hasLength(1));
      expect(await RideRepository.search({'destination': 'Sousse'}), isEmpty);
      expect(await RideRepository.search({'maxPrice': '3'}), isEmpty);
      expect(await RideRepository.search({'minSeats': '4'}), isEmpty);
    });

    test('le conducteur ne voit pas ses propres trajets dans la recherche', () async {
      FirestoreService.uid = 'amira';
      expect(await RideRepository.search({}), isEmpty);
    });

    test('publier un trajet', () async {
      await RideRepository.publish({'from': 'Bardo', 'to': 'Lac 2', 'date': day(3), 'time': '09:00', 'seats': 2, 'price': 5.0});
      final mine = (await db.collection('rides').where('driverId', isEqualTo: 'demo').get()).docs;
      expect(mine, hasLength(1));
      expect(mine.first.data()['seatsLeft'], 2);
      expect(mine.first.data()['status'], 'open');
    });

    test('publier dans le passé est refusé', () async {
      final e = await error(() => RideRepository.publish({'from': 'A', 'to': 'B', 'date': day(-1), 'time': '09:00', 'seats': 2, 'price': 5.0}));
      expect((e as ApiException).message, 'Date/heure invalide');
    });
  });

  group('Réservation', () {
    test('demander une place crée la demande et prévient le conducteur', () async {
      await BookingRepository.request('future');
      final b = (await db.collection('bookings').get()).docs.single.data();
      expect(b['status'], 'pending');
      expect(b['driverId'], 'amira');
      final n = await notificationsOf(db, 'amira');
      expect(n.single['type'], 'booking_new');
      expect(n.single['data']['name'], 'Demo');
      expect(n.single['pushed'], false); // le serveur push l'enverra
      expect((await RideRepository.search({})).single.myBookingStatus, 'pending');
    });

    test('double demande, propre trajet, trajet passé : refusés', () async {
      await BookingRepository.request('future');
      expect((await error(() => BookingRepository.request('future')) as ApiException).message, 'Vous avez déjà une demande pour ce trajet');
      expect((await error(() => BookingRepository.request('past')) as ApiException).message, 'Ce trajet est déjà passé');
      FirestoreService.uid = 'amira';
      expect((await error(() => BookingRepository.request('future')) as ApiException).message, 'Vous ne pouvez pas réserver votre propre trajet');
    });

    test('le conducteur accepte : une place en moins, le passager est prévenu', () async {
      await BookingRepository.request('future');
      final id = (await db.collection('bookings').get()).docs.single.id;
      FirestoreService.uid = 'amira';
      await BookingRepository.respond(id, true);
      expect((await db.doc('bookings/$id').get()).data()!['status'], 'accepted');
      expect((await db.doc('rides/future').get()).data()!['seatsLeft'], 2);
      expect((await notificationsOf(db, 'demo')).single['type'], 'booking_accepted');
      expect((await error(() => BookingRepository.respond(id, false)) as ApiException).message, 'Demande déjà traitée');
    });

    test('seul le conducteur peut répondre', () async {
      await BookingRepository.request('future');
      final id = (await db.collection('bookings').get()).docs.single.id;
      FirestoreService.uid = 'sarra';
      expect((await error(() => BookingRepository.respond(id, true)) as ApiException).message, 'Réservation introuvable');
    });

    test('le passager annule une place acceptée : la place est rendue', () async {
      final id = await acceptedBooking(db, 'future', 'demo');
      await BookingRepository.cancel(id);
      expect((await db.doc('bookings/$id').get()).data()!['status'], 'cancelled');
      expect((await db.doc('rides/future').get()).data()!['seatsLeft'], 3);
      expect((await notificationsOf(db, 'amira')).single['type'], 'booking_cancelled');
    });

    test('le conducteur annule le trajet : demandes annulées, passagers prévenus', () async {
      final id = await acceptedBooking(db, 'future', 'demo');
      FirestoreService.uid = 'amira';
      await RideRepository.cancel('future');
      expect((await db.doc('rides/future').get()).data()!['status'], 'cancelled');
      expect((await db.doc('bookings/$id').get()).data()!['status'], 'cancelled');
      expect((await notificationsOf(db, 'demo')).single['type'], 'ride_cancelled');
    });

    test('mes réservations et mes trajets', () async {
      await acceptedBooking(db, 'future', 'demo');
      final mine = await BookingRepository.myBookings();
      expect(mine.single.ride!.route, 'Ariana → Esprit Ghazela');
      expect(mine.single.ride!.driver!.name, 'Amira');
      FirestoreService.uid = 'amira';
      final rides = await RideRepository.myRides();
      expect(rides, hasLength(2));
      expect(rides.firstWhere((r) => r.id == 'future').bookings.single.passenger!.name, 'Demo');
    });
  });

  group('Détails du trajet', () {
    test('le passager accepté voit sa réservation et le numéro du conducteur', () async {
      await acceptedBooking(db, 'future', 'demo');
      final d = await RideRepository.details('future');
      expect(d.isDriver, isFalse);
      expect(d.iAmAccepted, isTrue);
      expect(d.driver.phone, '22123456');
      expect(d.finished, isFalse);
      expect(d.toRate, isEmpty); // pas de note avant le trajet
    });

    test('un autre utilisateur ne voit que les passagers acceptés', () async {
      await acceptedBooking(db, 'future', 'demo');
      await db.collection('bookings').add({'rideId': 'future', 'passengerId': 'x', 'driverId': 'amira', 'status': 'pending', 'createdAt': DateTime.now().toIso8601String()});
      FirestoreService.uid = 'sarra';
      final d = await RideRepository.details('future');
      expect(d.myBooking, isNull);
      expect(d.ride.bookings.every((b) => b.status == 'accepted'), isTrue);
      FirestoreService.uid = 'amira';
      expect((await RideRepository.details('future')).ride.bookings, hasLength(2)); // le conducteur voit tout
    });

    test('le passager accepté termine le trajet et peut noter le conducteur immédiatement', () async {
      final bookingId = await acceptedBooking(db, 'future', 'demo');
      await db.collection('bookings').add({
        'rideId': 'future',
        'passengerId': 'sarra',
        'driverId': 'amira',
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });

      await RideRepository.end('future', bookingId);

      final ride = (await db.doc('rides/future').get()).data()!;
      expect(ride['status'], 'completed');
      expect(ride['completionBookingId'], bookingId);
      final pending = (await db.collection('bookings').where('passengerId', isEqualTo: 'sarra').get()).docs.single;
      expect(pending.data()['status'], 'declined');
      expect((await notificationsOf(db, 'sarra')).single['type'], 'ride_ended');
      final details = await RideRepository.details('future');
      expect(details.finished, isTrue);
      expect(details.toRate.single.id, 'amira');

      await ReviewRepository.add('future', 'amira', 5, '');
      expect((await RideRepository.details('future')).toRate, isEmpty);
    });

    test('seul le passager accepté peut terminer le trajet', () async {
      final bookingId = await acceptedBooking(db, 'future', 'demo');
      FirestoreService.uid = 'sarra';
      expect(
        (await error(() => RideRepository.end('future', bookingId)) as ApiException).message,
        'Réservation introuvable',
      );
      FirestoreService.uid = 'amira';
      expect(
        (await error(() => RideRepository.end('future', bookingId)) as ApiException).message,
        'Réservation introuvable',
      );
    });
  });

  group('Avis', () {
    test('après le trajet, le passager note le conducteur ; la note moyenne change', () async {
      await acceptedBooking(db, 'past', 'demo');
      final d = await RideRepository.details('past');
      expect(d.finished, isTrue);
      expect(d.toRate.single.id, 'amira');

      await ReviewRepository.add('past', 'amira', 3, 'Correct');
      final amira = await UserRepository.publicUser('amira');
      expect(amira.ratingCount, 3);
      expect(amira.rating, 4.0); // (9 + 3) / 3
      expect(amira.reviews.single.from, 'Demo');
      expect(amira.reviews.single.comment, 'Correct');
      expect((await notificationsOf(db, 'amira')).single['type'], 'review');
      expect((await RideRepository.details('past')).toRate, isEmpty);
    });

    test('règles : une seule fois, seulement après le trajet, seulement entre participants', () async {
      await acceptedBooking(db, 'past', 'demo');
      await acceptedBooking(db, 'future', 'demo');
      await ReviewRepository.add('past', 'amira', 5, '');
      expect((await error(() => ReviewRepository.add('past', 'amira', 5, '')) as ApiException).message, 'Avis déjà envoyé');
      expect((await error(() => ReviewRepository.add('future', 'amira', 5, '')) as ApiException).message, 'Vous pourrez noter après le trajet');
      expect((await error(() => ReviewRepository.add('past', 'amira', 9, '')) as ApiException).message, 'Note entre 1 et 5');
      FirestoreService.uid = 'sarra';
      expect((await error(() => ReviewRepository.add('past', 'amira', 1, '')) as ApiException).message,
          'Vous ne pouvez pas noter cette personne pour ce trajet');
    });

    test('le conducteur peut noter son passager', () async {
      await acceptedBooking(db, 'past', 'demo');
      FirestoreService.uid = 'amira';
      expect((await RideRepository.details('past')).toRate.single.id, 'demo');
      await ReviewRepository.add('past', 'demo', 5, 'Ponctuel');
      FirestoreService.uid = 'demo';
      expect((await UserRepository.me()).rating, 5.0);
    });
  });

  group('Notifications et profil', () {
    test('liste triée et tout marquer comme lu', () async {
      FirestoreService.uid = 'demo';
      await BookingRepository.request('future'); // notifie amira
      FirestoreService.uid = 'amira';
      expect((await NotificationRepository.list()).single.type, 'booking_new');
      await NotificationRepository.markAllRead();
      expect((await NotificationRepository.list()).single.read, isTrue);
    });

    test('créer et modifier son profil', () async {
      FirestoreService.uid = 'newbie';
      final u = await UserRepository.createProfile('New@Esprit.Univ.tn', 'Newbie');
      expect(u.email, 'new@esprit.univ.tn');
      expect(u.rating, isNull);
      final updated = await UserRepository.updateProfile({'phone': '22000000', 'car': {'model': 'Polo', 'plate': '200 TU 9'}});
      expect(updated.hasCar, isTrue);
      expect(updated.phone, '22000000');
    });
  });
}
