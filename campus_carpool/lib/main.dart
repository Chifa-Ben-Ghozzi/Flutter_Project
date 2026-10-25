import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api.dart';
import 'firebase_options.dart';
import 'l10n.dart';
import 'providers/auth_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/settings_provider.dart';
import 'routes.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/ride_details_screen.dart';
import 'screens/splash_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (projet configuré par `flutterfire configure` -> firebase_options.dart)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Cache local de Firestore : l'app affiche les dernières données même hors ligne
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // Objets d'état partagés (Provider), créés une seule fois
  final l10n = L10n();
  final settings = SettingsProvider();
  final auth = AuthProvider();
  final notifs = NotificationsProvider(auth, l10n);
  await Future.wait([l10n.load(), settings.load()]);
  l10n.addListener(notifs.syncLanguage); // langue des notifications push

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: l10n),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: notifs),
      ChangeNotifierProvider.value(value: Api.network),
    ],
    // L10nScope : context.tr('clé') partout, y compris dans les dialogues
    child: L10nScope(l10n: l10n, child: CarpoolApp(init: () => _init(auth, notifs))),
  ));
}

/// Pendant le splash : reprend la session puis démarre les notifications.
Future<void> _init(AuthProvider auth, NotificationsProvider notifs) async {
  await auth.init();
  notifs.onOpenRide = _openRideFromNotification;
  await notifs.init();
  final launchRide = await notifs.launchRideId();
  if (launchRide != null) {
    Future.delayed(const Duration(seconds: 3), () => _openRideFromNotification(launchRide));
  }
}

// Toucher une notification du téléphone ouvre le trajet concerné
void _openRideFromNotification(String rideId) {
  final ctx = navigatorKey.currentContext;
  if (ctx != null && ctx.read<AuthProvider>().loggedIn) openRide(ctx, rideId);
}

const _seed = Color(0xFF3F51B5);

ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      useMaterial3: true,
      cardTheme: const CardThemeData(elevation: 1),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

class CarpoolApp extends StatelessWidget {
  final Future<void> Function()? init;
  const CarpoolApp({super.key, this.init});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10n>();
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'Campus Carpool',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: Locale(l10n.lang),
      // Thème clair / sombre (choix dans Profil > Paramètres)
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: settings.themeMode,
      // Navigation par routes nommées (voir routes.dart)
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      onUnknownRoute: AppRoutes.onUnknownRoute,
      home: SplashScreen(
        init: init,
        next: Selector<AuthProvider, bool>(
          selector: (_, a) => a.loggedIn,
          builder: (_, logged, __) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: logged ? const HomeScreen() : const AuthScreen(),
          ),
        ),
      ),
    );
  }
}
