import 'package:campus_carpool/models.dart';
import 'package:campus_carpool/repositories/connection_repository.dart';
import 'package:campus_carpool/screens/search_screen.dart';
import 'package:campus_carpool/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_data.dart';
import 'helpers.dart';

// Coordonnées réelles : Sousse → Nabeul fait environ 71 km à vol d'oiseau, soit 1 h 20 estimée.
const sousse = (35.8256, 10.6411);
const nabeul = (36.4561, 10.7376);
const tunis = (36.8065, 10.1815);

void main() {
  late FakeFirebaseFirestore db;

  /// Ajoute un trajet demain à [time] ; sans coordonnées si [a] ou [b] est null.
  Future<void> ride(String id, String from, String to, String time,
      {(double, double)? a, (double, double)? b, String driver = 'amira', num price = 5, int seats = 3, int inDays = 1}) =>
      db.doc('rides/$id').set({
        'driverId': driver,
        'from': from,
        'to': to,
        'date': day(inDays),
        'time': time,
        'dateTime': Timestamp.fromDate(DateTime.parse('${day(inDays)}T$time:00')),
        'seats': seats,
        'seatsLeft': seats,
        'price': price,
        'status': 'open',
        if (a != null) ...{'fromLat': a.$1, 'fromLng': a.$2},
        if (b != null) ...{'toLat': b.$1, 'toLng': b.$2},
      });

  Future<List<RideConnection>> connect({String? date, double? maxPrice, int? minSeats}) =>
      ConnectionRepository.find(from: 'Sousse', to: 'Tunis', date: date, maxPrice: maxPrice, minSeats: minSeats);

  setUp(() async {
    db = await fakeDb(); // le service d'itinéraire ne répond pas dans les tests : durée estimée
    FirestoreService.uid = 'demo';
    ConnectionRepository.clearCache();
    // Premier trajet : départ 08:00, arrivée estimée 09:20
    await ride('s-n', 'Sousse', 'Nabeul', '08:00', a: sousse, b: nabeul, price: 6);
  });

  group('Correspondances', () {
    test('durée estimée à partir de la distance', () {
      final km = ConnectionRepository.distanceKm(sousse.$1, sousse.$2, nabeul.$1, nabeul.$2);
      expect(km, closeTo(70.6, 1));
      expect(ConnectionRepository.estimateDuration(km), const Duration(minutes: 80));
    });

    test('deux trajets qui s\'enchaînent avec exactement 10 min de battement', () async {
      await ride('n-t', 'Nabeul', 'Tunis', '09:30', a: nabeul, b: tunis, driver: 'sarra', price: 4);
      final c = (await connect()).single;
      expect((c.first.id, c.second.id), ('s-n', 'n-t'));
      expect(c.via, 'Nabeul');
      expect((c.arrival.hour, c.arrival.minute), (9, 20));
      expect(c.wait, const Duration(minutes: 10));
      expect(c.price, 10);
    });

    test('moins de 10 min de battement : refusé', () async {
      await ride('n-t', 'Nabeul', 'Tunis', '09:25', a: nabeul, b: tunis);
      expect(await connect(), isEmpty);
    });

    test('plus de 3 h d\'attente, ou second trajet avant le premier : refusé', () async {
      await ride('tard', 'Nabeul', 'Tunis', '13:00', a: nabeul, b: tunis);
      await ride('tot', 'Nabeul', 'Tunis', '07:00', a: nabeul, b: tunis);
      expect(await connect(), isEmpty);
    });

    test('les deux trajets doivent se rejoindre au même endroit', () async {
      await ride('ailleurs', 'Hammamet', 'Tunis', '10:00', a: (36.4000, 10.6167), b: tunis);
      expect(await connect(), isEmpty);
      // Nom différent mais à moins de 5 km : accepté
      await ride('proche', 'Gare routière', 'Tunis', '10:00', a: (36.4600, 10.7400), b: tunis);
      expect((await connect()).single.second.id, 'proche');
    });

    test('même nom de lieu sans coordonnées côté second trajet : accepté', () async {
      await ride('n-t', 'nabeul centre', 'Tunis', '10:00');
      expect((await connect()).single.wait, const Duration(minutes: 40));
    });

    test('premier trajet sans coordonnées : durée inconnue, pas de proposition', () async {
      await db.doc('rides/s-n').delete();
      await ride('s-n2', 'Sousse', 'Nabeul', '08:00');
      await ride('n-t', 'Nabeul', 'Tunis', '10:00', a: nabeul, b: tunis);
      expect(await connect(), isEmpty);
    });

    test('filtres : date, prix total et places', () async {
      await ride('n-t', 'Nabeul', 'Tunis', '09:30', a: nabeul, b: tunis, price: 4, seats: 2);
      expect(await connect(date: day(1)), hasLength(1));
      expect(await connect(date: day(2)), isEmpty);
      expect(await connect(maxPrice: 10), hasLength(1));
      expect(await connect(maxPrice: 9), isEmpty);
      expect(await connect(minSeats: 2), hasLength(1));
      expect(await connect(minSeats: 3), isEmpty);
    });

    test('mes propres trajets et les trajets complets sont exclus ; tri par départ', () async {
      await ride('n-t', 'Nabeul', 'Tunis', '09:30', a: nabeul, b: tunis);
      await ride('mien', 'Nabeul', 'Tunis', '09:40', a: nabeul, b: tunis, driver: 'demo');
      await ride('plein', 'Nabeul', 'Tunis', '09:45', a: nabeul, b: tunis, seats: 0);
      await ride('s-n-tot', 'Sousse', 'Nabeul', '07:30', a: sousse, b: nabeul, driver: 'sarra');
      final found = await connect();
      // 07:30 → arrivée 08:50 → 09:30 (40 min) ; 08:00 → arrivée 09:20 → 09:30 (10 min)
      expect(found.map((c) => (c.first.id, c.second.id)), [('s-n-tot', 'n-t'), ('s-n', 'n-t')]);
    });
  });

  group('Recherche avec correspondance', () {
    Future<void> search(WidgetTester tester, String from, String to) async {
      await tester.pumpWidget(testApp(const Scaffold(body: SearchScreen())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), from);
      await tester.enterText(find.byType(TextField).at(1), to);
      await tester.tap(find.text('Rechercher'));
      await tester.pumpAndSettle();
    }

    testWidgets('aucun trajet direct : propose les deux covoiturages et réserve les deux', (tester) async {
      await ride('n-t', 'Nabeul', 'Tunis', '09:30', a: nabeul, b: tunis, driver: 'sarra', price: 4);
      await search(tester, 'Sousse', 'Tunis');

      expect(find.text('0 offres trouvées'), findsOneWidget);
      expect(find.text('Avec une correspondance'), findsOneWidget);
      expect(find.text('Sousse → Nabeul'), findsOneWidget);
      expect(find.text('Nabeul → Tunis'), findsOneWidget);
      expect(find.text('Correspondance à Nabeul · arrivée vers 09:20 · 10 min d’attente'), findsOneWidget);

      await tester.ensureVisible(find.text('Demander les 2 places'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demander les 2 places'));
      await tester.pumpAndSettle();
      final bookings = (await db.collection('bookings').where('passengerId', isEqualTo: 'demo').get()).docs;
      expect(bookings.map((b) => b.data()['rideId']).toSet(), {'s-n', 'n-t'});
      expect(find.text('Demander les 2 places'), findsNothing);
    });

    testWidgets('un trajet direct existe : pas de correspondance proposée', (tester) async {
      await ride('n-t', 'Nabeul', 'Tunis', '09:30', a: nabeul, b: tunis);
      await ride('direct', 'Sousse', 'Tunis', '08:15', a: sousse, b: tunis);
      await search(tester, 'Sousse', 'Tunis');
      expect(find.text('1 offre trouvée'), findsOneWidget);
      expect(find.text('Avec une correspondance'), findsNothing);
    });

    testWidgets('ni direct ni correspondance : message habituel', (tester) async {
      await search(tester, 'Sousse', 'Tunis');
      expect(find.text('Avec une correspondance'), findsNothing);
      expect(find.textContaining('Aucun trajet trouvé'), findsOneWidget);
    });
  });
}
