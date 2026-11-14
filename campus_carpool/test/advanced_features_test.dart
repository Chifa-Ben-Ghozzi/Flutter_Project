import 'package:campus_carpool/models.dart';
import 'package:campus_carpool/repositories/alert_repository.dart';
import 'package:campus_carpool/repositories/chat_repository.dart';
import 'package:campus_carpool/repositories/ride_repository.dart';
import 'package:campus_carpool/screens/alerts_screen.dart';
import 'package:campus_carpool/screens/chat_screen.dart';
import 'package:campus_carpool/screens/post_ride_screen.dart';
import 'package:campus_carpool/services/exceptions.dart';
import 'package:campus_carpool/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_data.dart';
import 'helpers.dart';

/// Messagerie, alertes de trajet et trajets réguliers, sur une base Firestore en mémoire.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await fakeDb();
    FirestoreService.uid = 'demo';
  });

  group('Trajets réguliers', () {
    test('occurrences : lundi, mercredi et vendredi pendant 2 semaines', () {
      final monday = DateTime(2026, 11, 16, 8, 0); // un lundi
      final dates = RideRepository.occurrences(monday, {1, 3, 5}, 2);
      expect(dates.map((d) => d.day), [16, 18, 20, 23, 25, 27]);
      expect(dates.every((d) => d.hour == 8 && d.minute == 0), isTrue);
    });

    test('occurrences : le premier jour n\'est inclus que s\'il est coché', () {
      final monday = DateTime(2026, 11, 16, 8, 0);
      expect(RideRepository.occurrences(monday, {2}, 1).map((d) => d.day), [17]);
    });

    test('publier une série crée toutes les dates avec le même seriesId', () async {
      final first = DateTime.now().add(const Duration(days: 1));
      final second = first.add(const Duration(days: 1));
      final n = await RideRepository.publish({
        'from': 'Ariana',
        'to': 'Esprit',
        'date': day(1),
        'time': '08:00',
        'seats': 3,
        'price': 4,
        'repeatDays': [first.weekday, second.weekday],
        'repeatWeeks': 2,
      });
      expect(n, 4);
      final rides = (await db.collection('rides').where('driverId', isEqualTo: 'demo').get()).docs;
      expect(rides, hasLength(4));
      final series = rides.map((d) => d.data()['seriesId']).toSet();
      expect(series, hasLength(1));
      expect(series.single, isNotNull);
    });

    test('un trajet simple n\'a pas de seriesId', () async {
      expect(
          await RideRepository.publish(
              {'from': 'Ariana', 'to': 'Esprit', 'date': day(1), 'time': '08:00', 'seats': 3, 'price': 4}),
          1);
      final ride = (await db.collection('rides').where('driverId', isEqualTo: 'demo').get()).docs.single;
      expect(ride.data().containsKey('seriesId'), isFalse);
    });

    test('annuler la série annule toutes les dates à venir et prévient les passagers', () async {
      final d = DateTime.now().add(const Duration(days: 1));
      await RideRepository.publish({
        'from': 'Ariana',
        'to': 'Esprit',
        'date': day(1),
        'time': '08:00',
        'seats': 3,
        'price': 4,
        'repeatDays': [d.weekday],
        'repeatWeeks': 3,
      });
      final rides = (await db.collection('rides').where('driverId', isEqualTo: 'demo').get()).docs;
      // Sarra est acceptée sur une des dates
      await db.collection('bookings').add({
        'rideId': rides.first.id,
        'passengerId': 'sarra',
        'driverId': 'demo',
        'status': 'accepted',
        'createdAt': Timestamp.now(),
      });

      expect(await RideRepository.cancelSeries(rides.first.data()['seriesId']), 3);
      final after = (await db.collection('rides').where('driverId', isEqualTo: 'demo').get()).docs;
      expect(after.every((r) => r.data()['status'] == 'cancelled'), isTrue);
      expect((await notificationsOf(db, 'sarra')).single['type'], 'ride_cancelled');
    });

    testWidgets('formulaire : trajet régulier sans jour choisi -> erreur', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: PostRideScreen())));
      await tester.tap(find.text('Trajet régulier'));
      await tester.pumpAndSettle();
      expect(find.text('lun.'), findsOneWidget); // les jours de la semaine apparaissent
      await tester.ensureVisible(find.text('Publier').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publier').last);
      await tester.pump();
      expect(find.text('Choisissez au moins un jour'), findsOneWidget);
    });
  });

  group('Alertes de trajet', () {
    test('correspondance : départ, destination et prix maximum', () {
      const ride = Ride(
          id: 'r',
          driverId: 'x',
          from: 'Ariana Soghra',
          to: 'Esprit Ghazela',
          date: '2026-12-01',
          time: '08:00',
          seats: 3,
          seatsLeft: 3,
          price: 4,
          status: 'open');
      expect(const RideAlert(id: 'a', userId: 'u', to: 'esprit').matches(ride), isTrue);
      expect(const RideAlert(id: 'a', userId: 'u', from: 'ariana', to: 'ESPRIT').matches(ride), isTrue);
      expect(const RideAlert(id: 'a', userId: 'u', from: 'Sousse').matches(ride), isFalse);
      expect(const RideAlert(id: 'a', userId: 'u', to: 'esprit', maxPrice: 3).matches(ride), isFalse);
      expect(const RideAlert(id: 'a', userId: 'u', to: 'esprit', maxPrice: 4).matches(ride), isTrue);
    });

    test('créer, lister, refuser les doublons et les alertes vides, supprimer', () async {
      await AlertRepository.add(from: 'Ariana', to: 'Esprit', maxPrice: 5);
      expect(() => AlertRepository.add(from: 'ariana', to: 'esprit', maxPrice: 5), throwsA(isA<ApiException>()));
      expect(() => AlertRepository.add(from: '  ', to: ''), throwsA(isA<ApiException>()));
      final mine = await AlertRepository.mine();
      expect(mine.single.from, 'Ariana');
      expect(mine.single.maxPrice, 5);
      await AlertRepository.delete(mine.single.id);
      expect(await AlertRepository.mine(), isEmpty);
    });

    test('publier un trajet prévient les alertes correspondantes, une fois par personne', () async {
      Future<void> alert(String user, String from, String to) => db
          .collection('alerts')
          .add({'userId': user, 'from': from, 'to': to, 'maxPrice': null, 'createdAt': Timestamp.now()});
      await alert('sarra', '', 'esprit');
      await alert('sarra', 'ariana', ''); // deuxième alerte de Sarra qui correspond aussi
      await alert('amira', 'Sousse', ''); // ne correspond pas
      await alert('demo', '', 'esprit'); // ma propre alerte : pas de notification

      final d = DateTime.now().add(const Duration(days: 1));
      await RideRepository.publish({
        'from': 'Ariana',
        'to': 'Esprit Ghazela',
        'date': day(1),
        'time': '08:00',
        'seats': 3,
        'price': 4,
        'repeatDays': [d.weekday],
        'repeatWeeks': 2,
      });

      final sarra = await notificationsOf(db, 'sarra');
      expect(sarra, hasLength(1)); // une seule notification pour toute la série
      expect(sarra.single['type'], 'ride_alert');
      expect(sarra.single['data']['name'], 'Demo');
      expect(sarra.single['data']['count'], 2);
      expect(await notificationsOf(db, 'amira'), isEmpty);
      expect(await notificationsOf(db, 'demo'), isEmpty);
    });

    testWidgets("écran des alertes : création par le formulaire", (tester) async {
      await tester.pumpWidget(testApp(const AlertsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucune alerte'), findsOneWidget);

      await tester.tap(find.text('Nouvelle alerte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer'));
      await tester.pump();
      expect(find.text('Indiquez un départ ou une destination'), findsOneWidget); // validator

      await tester.enterText(find.byType(TextFormField).at(1), 'Esprit');
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();
      expect(find.text('Partout → Esprit'), findsOneWidget);
      expect((await db.collection('alerts').get()).docs.single.data()['userId'], 'demo');
    });
  });

  group('Messagerie', () {
    late String booking;
    setUp(() async => booking = await acceptedBooking(db, 'future', 'demo'));

    test('le passager écrit, le conducteur lit en direct puis marque comme lu', () async {
      await ChatRepository.send(booking, '  Bonjour, où est le rendez-vous ?  ');
      final msg = (await db.collection('messages').get()).docs.single.data();
      expect(msg['from'], 'demo');
      expect(msg['to'], 'amira');
      expect(msg['text'], 'Bonjour, où est le rendez-vous ?');
      expect(msg['route'], 'Ariana → Esprit Ghazela');
      expect(msg['read'], isFalse);
      expect(msg['pushed'], isFalse); // le serveur push enverra la notification

      FirestoreService.uid = 'amira';
      final list = await ChatRepository.watch(booking).first;
      expect(list.single.fromName, 'Demo');
      final inbox = await ChatRepository.conversations().first;
      expect(inbox.single.otherName, 'Demo');
      expect(inbox.single.unread, 1);

      await ChatRepository.markRead(booking);
      expect((await ChatRepository.conversations().first).single.unread, 0);
    });

    test('conversation fermée ou étrangère : envoi refusé', () async {
      await db.doc('bookings/$booking').update({'status': 'cancelled'});
      expect(() => ChatRepository.send(booking, 'Salut'), throwsA(isA<ApiException>()));
      FirestoreService.uid = 'sarra'; // ne participe pas
      expect(() => ChatRepository.send(booking, 'Salut'), throwsA(isA<ApiException>()));
    });

    test('message vide refusé', () {
      expect(() => ChatRepository.send(booking, '   '), throwsA(isA<ApiException>()));
    });

    test('boîte de réception : regroupement par réservation, la plus récente en premier', () {
      ChatMessage m(String id, String booking, String from, String to, int minute, {bool read = false}) => ChatMessage(
          id: id,
          bookingId: booking,
          rideId: 'r',
          from: from,
          to: to,
          fromName: from,
          toName: to,
          text: id,
          createdAt: DateTime(2026, 1, 1, 10, minute),
          read: read);
      final convs = ChatRepository.group([
        m('a1', 'A', 'amira', 'demo', 1),
        m('a2', 'A', 'demo', 'amira', 2),
        m('b1', 'B', 'sarra', 'demo', 5),
        m('b2', 'B', 'sarra', 'demo', 6, read: true),
      ], 'demo');
      expect(convs.map((c) => c.bookingId), ['B', 'A']);
      expect(convs.first.otherName, 'sarra');
      expect(convs.first.unread, 1);
      expect(convs.last.otherName, 'amira'); // dernier message envoyé par moi : l'autre est le destinataire
      expect(convs.last.last.text, 'a2');
    });

    testWidgets('écran de conversation : envoyer un message et une réponse rapide', (tester) async {
      await tester.pumpWidget(testApp(ChatScreen(bookingId: booking)));
      await tester.pumpAndSettle();
      expect(find.text('Amira'), findsOneWidget); // en-tête
      expect(find.textContaining('Dites bonjour'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Je serai devant la porte');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Je serai devant la porte'), findsOneWidget);

      await tester.tap(find.text("J'aurai 5 min de retard"));
      await tester.pumpAndSettle();
      expect((await db.collection('messages').get()).docs, hasLength(2));
    });

    testWidgets('réservation annulée : la conversation est en lecture seule', (tester) async {
      await db.doc('bookings/$booking').update({'status': 'cancelled'});
      await tester.pumpWidget(testApp(ChatScreen(bookingId: booking)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Conversation fermée'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
