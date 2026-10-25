import 'package:campus_carpool/api.dart';
import 'package:campus_carpool/routes.dart';
import 'package:campus_carpool/screens/post_ride_screen.dart';
import 'package:campus_carpool/screens/ride_details_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_data.dart';
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

  group('Détails du trajet (Firestore en mémoire)', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = await fakeDb();
      Api.uid = 'demo';
    });

    testWidgets("affiche le trajet, réserve une place, puis propose d'annuler", (tester) async {
      await tester.pumpWidget(testApp(const RideDetailsScreen(rideId: 'future')));
      await tester.pumpAndSettle();

      expect(find.text('Ariana → Esprit Ghazela'), findsOneWidget);
      expect(find.text('Amira'), findsOneWidget);
      expect(find.text(' 4.5'), findsOneWidget); // note du conducteur
      expect(find.text('Appeler'), findsNothing); // pas encore accepté

      await tester.tap(find.text('Demander une place · 4 dt'));
      await tester.pumpAndSettle();

      expect((await db.collection('bookings').get()).docs.single.data()['status'], 'pending');
      expect(find.text('Demande envoyée au conducteur'), findsOneWidget);
      expect(find.text('Annuler ma demande'), findsOneWidget);
      expect(find.textContaining('une fois votre demande acceptée'), findsOneWidget);
    });

    testWidgets('passager accepté : boutons Appeler et WhatsApp', (tester) async {
      await acceptedBooking(db, 'future', 'demo');
      await tester.pumpWidget(testApp(const RideDetailsScreen(rideId: 'future')));
      await tester.pumpAndSettle();
      expect(find.text('Appeler'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Annuler ma place'), findsOneWidget);
    });

    testWidgets('trajet introuvable : message et bouton Réessayer', (tester) async {
      await tester.pumpWidget(testApp(const RideDetailsScreen(rideId: 'nexiste-pas')));
      await tester.pumpAndSettle();
      expect(find.text('Trajet introuvable'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}
