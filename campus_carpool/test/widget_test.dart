import 'dart:convert';

import 'package:campus_carpool/api.dart';
import 'package:campus_carpool/routes.dart';
import 'package:campus_carpool/screens/post_ride_screen.dart';
import 'package:campus_carpool/screens/ride_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Formulaire "Publier un trajet" (Form + validators)', () {
    testWidgets('formulaire vide : erreurs sous les champs', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: PostRideScreen())));
      await tester.tap(find.text('Publier').last);
      await tester.pump();

      expect(find.text('Champ obligatoire'), findsNWidgets(2)); // départ + destination
      expect(find.text('Choisissez une date'), findsOneWidget);
      expect(find.text('Nombre (ex: 5 ou 4.5)'), findsOneWidget); // prix vide
    });

    testWidgets('valeurs incohérentes', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: PostRideScreen())));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Tunis'); // départ
      await tester.enterText(fields.at(1), 'tunis'); // destination
      await tester.enterText(fields.at(4), '12'); // places
      await tester.enterText(fields.at(5), '-3'); // prix
      await tester.tap(find.text('Publier').last);
      await tester.pump();

      expect(find.text('La destination doit être différente du départ'), findsOneWidget);
      expect(find.text('Entre 1 et 8'), findsOneWidget);
      expect(find.text('Prix positif'), findsOneWidget);
    });

    testWidgets('en anglais, les messages sont traduits', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: PostRideScreen()), lang: 'en'));
      expect(find.text('Post a ride'), findsOneWidget);
      await tester.tap(find.text('Post').last);
      await tester.pump();
      expect(find.text('Required field'), findsNWidgets(2));
      expect(find.text('Pick a date'), findsOneWidget);
    });
  });

  group('Routes nommées', () {
    testWidgets('route inconnue -> page "introuvable"', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(testApp(const SizedBox(), navigatorKey: key));
      key.currentState!.pushNamed('/nexiste-pas');
      await tester.pumpAndSettle();
      expect(find.text('Page introuvable'), findsOneWidget);
    });

    test("la route /ride reçoit l'id du trajet en argument", () {
      final route = AppRoutes.onGenerateRoute(const RouteSettings(name: AppRoutes.rideDetails, arguments: 'abc123'));
      expect(route, isA<MaterialPageRoute<bool>>());
      expect(route!.settings.arguments, 'abc123');
    });
  });

  group('Détails du trajet + API (http MockClient)', () {
    // Faux serveur : un trajet, puis une demande en attente après la réservation
    late List<String> calls;
    var booked = false;

    Map<String, dynamic> details() => {
          'id': 'r1',
          'driverId': 'u1',
          'from': 'Ariana',
          'to': 'Esprit',
          'date': '2099-01-01',
          'time': '08:30',
          'seats': 3,
          'seatsLeft': 2,
          'price': 4,
          'status': 'open',
          'driver': {'id': 'u1', 'name': 'Amira', 'phone': '22123456', 'car': {'model': 'Clio', 'plate': '215 TU 1'}, 'rating': 4.5, 'ratingCount': 2},
          'isDriver': false,
          'finished': false,
          'myBooking': booked ? {'id': 'b1', 'rideId': 'r1', 'passengerId': 'me', 'status': 'pending'} : null,
          'bookings': [],
          'toRate': [],
        };

    setUp(() {
      calls = [];
      booked = false;
      Api.token = 'test-token';
      Api.client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        expect(req.headers['Authorization'], 'Bearer test-token');
        if (req.method == 'POST' && req.url.path == '/rides/r1/book') {
          booked = true;
          return http.Response('{}', 200);
        }
        if (req.url.path == '/rides/r1') return http.Response(jsonEncode(details()), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        return http.Response('{"error":"Trajet introuvable"}', 404);
      });
    });

    testWidgets('affiche le trajet, réserve une place, puis propose d\'annuler', (tester) async {
      await tester.pumpWidget(testApp(const RideDetailsScreen(rideId: 'r1')));
      await tester.pumpAndSettle();

      expect(find.text('Ariana → Esprit'), findsOneWidget);
      expect(find.text('Amira'), findsOneWidget);
      expect(find.text(' 4.5'), findsOneWidget); // note du conducteur
      expect(find.text('Appeler'), findsNothing); // pas encore accepté

      await tester.tap(find.text('Demander une place · 4 dt'));
      await tester.pumpAndSettle();

      expect(calls, contains('POST /rides/r1/book'));
      expect(find.text('Demande envoyée au conducteur'), findsOneWidget);
      expect(find.text('Annuler ma demande'), findsOneWidget);
      expect(find.textContaining('une fois votre demande acceptée'), findsOneWidget);
    });

    testWidgets('serveur injoignable : message d\'erreur', (tester) async {
      Api.client = MockClient((_) async => throw Exception('offline'));
      await tester.pumpWidget(testApp(const RideDetailsScreen(rideId: 'r1')));
      await tester.pumpAndSettle();
      expect(find.text('Serveur indisponible. Vérifiez votre connexion.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(Api.network.online, isFalse);
    });
  });
}
