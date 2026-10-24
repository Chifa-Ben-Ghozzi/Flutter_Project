import 'package:campus_carpool/api.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_data.dart';

/// Logique métier de l'app sur une base Firestore en mémoire (FakeFirebaseFirestore).
void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = await fakeDb();
    Api.uid = 'demo';
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
      final rides = await Api.searchRides({});
      expect(rides.map((r) => r.id), ['future']); // pas le trajet passé
      expect(rides.first.driver!.name, 'Amira');
      expect(rides.first.driver!.rating, 4.5); // 9 / 2
      expect(rides.first.myBookingStatus, isNull);
    });

    test('filtres : destination, prix max, places min', () async {
      expect(await Api.searchRides({'destination': 'esprit'}), hasLength(1));
      expect(await Api.searchRides({'destination': 'Sousse'}), isEmpty);
      expect(await Api.searchRides({'maxPrice': '3'}), isEmpty);
      expect(await Api.searchRides({'minSeats': '4'}), isEmpty);
    });

    test('le conducteur ne voit pas ses propres trajets dans la recherche', () async {
      Api.uid = 'amira';
      expect(await Api.searchRides({}), isEmpty);
    });

    test('publier un trajet', () async {
      await Api.postRide({'from': 'Bardo', 'to': 'Lac 2', 'date': day(3), 'time': '09:00', 'seats': 2, 'price': 5.0});
      final mine = (await db.collection('rides').where('driverId', isEqualTo: 'demo').get()).docs;
      expect(mine, hasLength(1));
      expect(mine.first.data()['seatsLeft'], 2);
      expect(mine.first.data()['status'], 'open');
    });

    test('publier dans le passé est refusé', () async {
      final e = await error(() => Api.postRide({'from': 'A', 'to': 'B', 'date': day(-1), 'time': '09:00', 'seats': 2, 'price': 5.0}));
      expect((e as ApiException).message, 'Date/heure invalide');
    });
  });

  group('Réservation', () {
    test('demander une place crée la demande et prévient le conducteur', () async {
      await Api.book('future');
      final b = (await db.collection('bookings').get()).docs.single.data();
      expect(b['status'], 'pending');
      expect(b['driverId'], 'amira');
      final n = await notificationsOf(db, 'amira');
      expect(n.single['type'], 'booking_new');
      expect(n.single['data']['name'], 'Demo');
      expect(n.single['pushed'], false); // le serveur push l'enverra
      expect((await Api.searchRides({})).single.myBookingStatus, 'pending');
    });

    test('double demande, propre trajet, trajet passé : refusés', () async {
      await Api.book('future');
      expect((await error(() => Api.book('future')) as ApiException).message, 'Vous avez déjà une demande pour ce trajet');
      expect((await error(() => Api.book('past')) as ApiException).message, 'Ce trajet est déjà passé');
      Api.uid = 'amira';
      expect((await error(() => Api.book('future')) as ApiException).message, 'Vous ne pouvez pas réserver votre propre trajet');
    });

    test('le conducteur accepte : une place en moins, le passager est prévenu', () async {
      await Api.book('future');
      final id = (await db.collection('bookings').get()).docs.single.id;
      Api.uid = 'amira';
      await Api.respond(id, true);
      expect((await db.doc('bookings/$id').get()).data()!['status'], 'accepted');
      expect((await db.doc('rides/future').get()).data()!['seatsLeft'], 2);
      expect((await notificationsOf(db, 'demo')).single['type'], 'booking_accepted');
      expect((await error(() => Api.respond(id, false)) as ApiException).message, 'Demande déjà traitée');
    });

    test('seul le conducteur peut répondre', () async {
      await Api.book('future');
      final id = (await db.collection('bookings').get()).docs.single.id;
      Api.uid = 'sarra';
      expect((await error(() => Api.respond(id, true)) as ApiException).message, 'Réservation introuvable');
    });

    test('le passager annule une place acceptée : la place est rendue', () async {
      final id = await acceptedBooking(db, 'future', 'demo');
      await Api.cancelBooking(id);
      expect((await db.doc('bookings/$id').get()).data()!['status'], 'cancelled');
      expect((await db.doc('rides/future').get()).data()!['seatsLeft'], 3);
      expect((await notificationsOf(db, 'amira')).single['type'], 'booking_cancelled');
    });

    test('le conducteur annule le trajet : demandes annulées, passagers prévenus', () async {
      final id = await acceptedBooking(db, 'future', 'demo');
      Api.uid = 'amira';
      await Api.cancelRide('future');
      expect((await db.doc('rides/future').get()).data()!['status'], 'cancelled');
      expect((await db.doc('bookings/$id').get()).data()!['status'], 'cancelled');
      expect((await notificationsOf(db, 'demo')).single['type'], 'ride_cancelled');
    });

    test('mes réservations et mes trajets', () async {
      await acceptedBooking(db, 'future', 'demo');
      final mine = await Api.myBookings();
      expect(mine.single.ride!.route, 'Ariana → Esprit Ghazela');
      expect(mine.single.ride!.driver!.name, 'Amira');
      Api.uid = 'amira';
      final rides = await Api.myRides();
      expect(rides, hasLength(2));
      expect(rides.firstWhere((r) => r.id == 'future').bookings.single.passenger!.name, 'Demo');
    });
  });

  group('Détails du trajet', () {
    test('le passager accepté voit sa réservation et le numéro du conducteur', () async {
      await acceptedBooking(db, 'future', 'demo');
      final d = await Api.rideDetails('future');
      expect(d.isDriver, isFalse);
      expect(d.iAmAccepted, isTrue);
      expect(d.driver.phone, '22123456');
      expect(d.finished, isFalse);
      expect(d.toRate, isEmpty); // pas de note avant le trajet
    });

    test('un autre utilisateur ne voit que les passagers acceptés', () async {
      await acceptedBooking(db, 'future', 'demo');
      await db.collection('bookings').add({'rideId': 'future', 'passengerId': 'x', 'driverId': 'amira', 'status': 'pending', 'createdAt': DateTime.now().toIso8601String()});
      Api.uid = 'sarra';
      final d = await Api.rideDetails('future');
      expect(d.myBooking, isNull);
      expect(d.ride.bookings.every((b) => b.status == 'accepted'), isTrue);
      Api.uid = 'amira';
      expect((await Api.rideDetails('future')).ride.bookings, hasLength(2)); // le conducteur voit tout
    });
  });

  group('Avis', () {
    test('après le trajet, le passager note le conducteur ; la note moyenne change', () async {
      await acceptedBooking(db, 'past', 'demo');
      final d = await Api.rideDetails('past');
      expect(d.finished, isTrue);
      expect(d.toRate.single.id, 'amira');

      await Api.review('past', 'amira', 3, 'Correct');
      final amira = await Api.publicUser('amira');
      expect(amira.ratingCount, 3);
      expect(amira.rating, 4.0); // (9 + 3) / 3
      expect(amira.reviews.single.from, 'Demo');
      expect(amira.reviews.single.comment, 'Correct');
      expect((await notificationsOf(db, 'amira')).single['type'], 'review');
      expect((await Api.rideDetails('past')).toRate, isEmpty);
    });

    test('règles : une seule fois, seulement après le trajet, seulement entre participants', () async {
      await acceptedBooking(db, 'past', 'demo');
      await acceptedBooking(db, 'future', 'demo');
      await Api.review('past', 'amira', 5, '');
      expect((await error(() => Api.review('past', 'amira', 5, '')) as ApiException).message, 'Avis déjà envoyé');
      expect((await error(() => Api.review('future', 'amira', 5, '')) as ApiException).message, 'Vous pourrez noter après le trajet');
      expect((await error(() => Api.review('past', 'amira', 9, '')) as ApiException).message, 'Note entre 1 et 5');
      Api.uid = 'sarra';
      expect((await error(() => Api.review('past', 'amira', 1, '')) as ApiException).message,
          'Vous ne pouvez pas noter cette personne pour ce trajet');
    });

    test('le conducteur peut noter son passager', () async {
      await acceptedBooking(db, 'past', 'demo');
      Api.uid = 'amira';
      expect((await Api.rideDetails('past')).toRate.single.id, 'demo');
      await Api.review('past', 'demo', 5, 'Ponctuel');
      Api.uid = 'demo';
      expect((await Api.me()).rating, 5.0);
    });
  });

  group('Notifications et profil', () {
    test('liste triée et tout marquer comme lu', () async {
      Api.uid = 'demo';
      await Api.book('future'); // notifie amira
      Api.uid = 'amira';
      expect((await Api.notifications()).single.type, 'booking_new');
      await Api.markNotificationsRead();
      expect((await Api.notifications()).single.read, isTrue);
    });

    test('créer et modifier son profil', () async {
      Api.uid = 'newbie';
      final u = await Api.createProfile('New@Esprit.Univ.tn', 'Newbie');
      expect(u.email, 'new@esprit.univ.tn');
      expect(u.rating, isNull);
      final updated = await Api.updateProfile({'phone': '22000000', 'car': {'model': 'Polo', 'plate': '200 TU 9'}});
      expect(updated.hasCar, isTrue);
      expect(updated.phone, '22000000');
    });
  });
}
