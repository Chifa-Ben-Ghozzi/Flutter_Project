import 'package:campus_carpool/api.dart';
import 'package:campus_carpool/routes.dart';
import 'package:campus_carpool/screens/search_screen.dart';
import 'package:campus_carpool/screens/auth_screen.dart';
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

  testWidgets('suggested signup password fills both password fields securely', (tester) async {
    await tester.pumpWidget(testApp(const AuthScreen()));
    await tester.tap(find.text('Pas de compte ? Inscription'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suggérer un mot de passe'));
    await tester.pump();

    final password = tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text;
    final confirmation = tester.widget<TextField>(find.byType(TextField).at(3)).controller!.text;
    expect(password, hasLength(16));
    expect(password, matches(RegExp(r'[a-z]')));
    expect(password, matches(RegExp(r'[A-Z]')));
    expect(password, matches(RegExp(r'\d')));
    expect(password, matches(RegExp(r'[^A-Za-z0-9]')));
    expect(confirmation, password);
    expect(find.text('Fort'), findsOneWidget);
  });

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

    testWidgets('le passager termine son trajet puis peut noter avec un commentaire facultatif', (tester) async {
      await acceptedBooking(db, 'future', 'demo');
      await tester.pumpWidget(testApp(const RideDetailsScreen(rideId: 'future')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminer le trajet'));
      await tester.pumpAndSettle();
      expect(find.text('Terminer ce trajet ?'), findsOneWidget);

      await tester.tap(find.text('Oui'));
      await tester.pumpAndSettle();
      expect(find.text('Trajet terminé'), findsOneWidget);

      final rateButton = find.text('Noter').last;
      await tester.scrollUntilVisible(rateButton, 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(rateButton);
      await tester.pumpAndSettle();
      expect(find.text('Noter Amira'), findsOneWidget);
      expect(find.text('Commentaire (facultatif)'), findsOneWidget);
    });
  });

  group('Recherche', () {
    setUp(() async {
      await fakeDb();
      Api.uid = 'demo';
    });

    testWidgets('affiche le nombre de trajets trouvés', (tester) async {
      await tester.pumpWidget(testApp(const Scaffold(body: SearchScreen())));
      await tester.pumpAndSettle();

      expect(find.text('1 offre trouvée'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), 'Sousse');
      await tester.tap(find.text('Rechercher'));
      await tester.pumpAndSettle();

      expect(find.text('0 offres trouvées'), findsOneWidget);
    });
  });
}
