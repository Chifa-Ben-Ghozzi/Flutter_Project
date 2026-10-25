import 'package:campus_carpool/api.dart';
import 'package:campus_carpool/l10n.dart';
import 'package:campus_carpool/models.dart';
import 'package:campus_carpool/providers/auth_provider.dart';
import 'package:campus_carpool/providers/notifications_provider.dart';
import 'package:campus_carpool/providers/settings_provider.dart';
import 'package:campus_carpool/routes.dart';
import 'package:campus_carpool/screens/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_data.dart';

/// Parcours complet de l'application connectée, sur une base Firestore en mémoire :
/// tous les onglets, les notifications en temps réel, le thème sombre et le changement de langue.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('parcours : onglets, notifications, thème, langue', (tester) async {
    final db = await fakeDb();
    // Demo est accepté sur le trajet d'Amira ; Sarra demande une place sur le trajet de Demo
    await acceptedBooking(db, 'future', 'demo');
    await db.doc('rides/mine').set({
      'driverId': 'demo', 'from': 'Esprit Ghazela', 'to': 'La Marsa', 'date': day(2), 'time': '17:00',
      'dateTime': Timestamp.fromDate(DateTime.parse('${day(2)}T17:00:00')),
      'seats': 3, 'seatsLeft': 3, 'price': 4, 'status': 'open',
    });
    await db.collection('bookings').add(
        {'rideId': 'mine', 'passengerId': 'sarra', 'driverId': 'demo', 'status': 'pending', 'createdAt': Timestamp.now()});
    await db.collection('notifications').add({
      'userId': 'demo', 'type': 'booking_accepted', 'rideId': 'future', 'read': false, 'pushed': true,
      'createdAt': Timestamp.now(),
      'data': {'name': 'Amira', 'from': 'Ariana', 'to': 'Esprit Ghazela', 'date': day(1), 'time': '08:30'},
    });

    final l10n = L10n('fr');
    final settings = SettingsProvider();
    final auth = AuthProvider();
    final notifications = NotificationsProvider(auth, l10n, enablePush: false);
    await notifications.init();
    auth.debugSignIn(const AppUser(
        id: 'demo', name: 'Demo', email: 'demo@esprit.univ.tn', phone: '22111222', carModel: 'Clio', carPlate: '215 TU 4521'));

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

    // Recherche : trajet d'Amira avec le statut de ma demande ; badge de la cloche : 1 non lue
    expect(find.text('Ariana → Esprit Ghazela'), findsOneWidget);
    expect(find.text('Acceptée'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Une nouvelle notification arrive en direct (temps réel Firestore) : le badge passe à 2
    await db.collection('notifications').add({
      'userId': 'demo', 'type': 'booking_new', 'rideId': 'mine', 'read': false, 'pushed': false,
      'createdAt': Timestamp.now(), 'data': {'name': 'Sarra', 'from': 'Esprit Ghazela', 'to': 'La Marsa', 'date': day(2), 'time': '17:00'},
    });
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    // Onglet "Publier" : formulaire
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();
    expect(find.text('Publier un trajet'), findsOneWidget);

    // Onglet "Mes trajets" : demande de Sarra avec boutons accepter / refuser
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
    expect(find.text('Search'), findsOneWidget);

    // Notifications : textes traduits ; ouvrir la liste marque tout comme lu
    await tester.tap(find.byIcon(Icons.notifications_active));
    await tester.pumpAndSettle();
    expect(find.text('Booking accepted ✅'), findsOneWidget);
    expect(find.textContaining('Sarra requested a seat'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(notifications.unread, 0);
    expect((await db.collection('notifications').where('read', isEqualTo: false).get()).docs, isEmpty);

    notifications.dispose();
  });
}
