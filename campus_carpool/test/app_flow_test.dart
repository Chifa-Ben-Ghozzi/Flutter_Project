import 'dart:convert';

import 'package:campus_carpool/api.dart';
import 'package:campus_carpool/l10n.dart';
import 'package:campus_carpool/providers/auth_provider.dart';
import 'package:campus_carpool/providers/notifications_provider.dart';
import 'package:campus_carpool/providers/settings_provider.dart';
import 'package:campus_carpool/routes.dart';
import 'package:campus_carpool/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parcours complet de l'application connectée, avec un faux serveur :
/// tous les onglets, les notifications, le thème sombre et le changement de langue.
void main() {
  final user = {
    'id': 'me',
    'email': 'demo@esprit.univ.tn',
    'name': 'Demo',
    'phone': '22111222',
    'car': {'model': 'Clio', 'plate': '215 TU 4521'},
    'photo': null,
    'rating': 4.5,
    'ratingCount': 4,
  };
  final driver = {'id': 'u1', 'name': 'Amira', 'phone': '23456789', 'car': {'model': 'Peugeot 208', 'plate': '220 TU 1187'}, 'rating': 5, 'ratingCount': 2};
  Map<String, dynamic> ride(String id, String date, {List bookings = const []}) => {
        'id': id, 'driverId': 'u1', 'from': 'La Marsa', 'to': 'Esprit Ghazela', 'date': date, 'time': '08:00',
        'seats': 3, 'seatsLeft': 2, 'price': 4, 'status': 'open', 'driver': driver, 'bookings': bookings,
      };
  final notifs = [
    {
      'id': 'n1', 'type': 'booking_accepted', 'title': 'Réservation acceptée ✅', 'body': '…', 'rideId': 'r1', 'read': false,
      'createdAt': DateTime.now().toIso8601String(),
      'data': {'name': 'Amira', 'from': 'La Marsa', 'to': 'Esprit Ghazela', 'date': '2099-01-01', 'time': '08:00'},
    },
  ];

  http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.client = MockClient((req) async {
      switch (req.url.path) {
        case '/auth/login':
          return json({'token': 't', 'user': user});
        case '/me':
          return json(user);
        case '/rides':
          return json([ride('r1', '2099-01-01')..['myBooking'] = 'accepted']);
        case '/rides/mine':
          return json([
            ride('r2', '2099-02-01', bookings: [
              {'id': 'b1', 'rideId': 'r2', 'passengerId': 'p1', 'status': 'pending', 'passenger': {'id': 'p1', 'name': 'Sarra'}},
            ]),
          ]);
        case '/bookings/mine':
          return json([
            {'id': 'b2', 'rideId': 'r1', 'passengerId': 'me', 'status': 'accepted', 'ride': ride('r1', '2099-01-01')},
          ]);
        case '/notifications/poll':
          return json({'unread': 1, 'fresh': []});
        case '/notifications':
          return json(notifs);
        case '/notifications/read':
          return json({'ok': true});
      }
      return http.Response('{"error":"?"}', 404);
    });
  });

  testWidgets('parcours : onglets, notifications, thème, langue', (tester) async {
    final l10n = L10n('fr');
    final settings = SettingsProvider();
    final auth = AuthProvider();
    final notifications = NotificationsProvider(auth, l10n);
    await notifications.init();
    await auth.login('demo@esprit.univ.tn', 'demo123');

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: l10n),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: Api.network),
      ],
      child: L10nScope(
        l10n: l10n,
        child: Consumer<SettingsProvider>(
          builder: (_, s, __) => MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: s.themeMode,
            routes: AppRoutes.routes,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: const HomeScreen(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Recherche : trajet affiché avec le statut de ma demande
    expect(find.text('La Marsa → Esprit Ghazela'), findsOneWidget);
    expect(find.text('Acceptée'), findsOneWidget);
    // Badge de la cloche : 1 non lue
    expect(find.text('1'), findsOneWidget);

    // Onglet "Publier" : formulaire
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();
    expect(find.text('Publier un trajet'), findsOneWidget);

    // Onglet "Mes trajets" : demande en attente avec boutons accepter / refuser
    await tester.tap(find.text('Mes trajets'));
    await tester.pumpAndSettle();
    expect(find.text('Sarra'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Onglet "Réservations"
    await tester.tap(find.text('Réservations'));
    await tester.pumpAndSettle();
    expect(find.textContaining('appeler le conducteur'), findsOneWidget);

    // Onglet "Profil" : statistiques (GridView) + formulaire pré-rempli
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('215 TU 4521'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('215 TU 4521'), findsOneWidget);

    // Thème sombre
    await tester.scrollUntilVisible(find.text('Sombre'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Sombre'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(HomeScreen))).brightness, Brightness.dark);

    // Langue anglaise : toute l'interface change
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // onglet

    // Notifications : texte traduit à partir des données
    await tester.tap(find.byIcon(Icons.notifications_active));
    await tester.pumpAndSettle();
    expect(find.text('Booking accepted ✅'), findsOneWidget);
    expect(find.textContaining('Amira accepted your request'), findsOneWidget);
    expect(notifications.unread, 0); // ouverte => tout marqué comme lu

    // Déconnexion : arrête la vérification périodique des notifications
    await auth.logout();
    notifications.dispose();
    await tester.pumpAndSettle();
  });
}
