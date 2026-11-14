import 'package:campus_carpool/l10n.dart';
import 'package:campus_carpool/providers/auth_provider.dart';
import 'package:campus_carpool/providers/chat_provider.dart';
import 'package:campus_carpool/providers/settings_provider.dart';
import 'package:campus_carpool/routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:campus_carpool/services/firestore_service.dart';

/// Monte un écran avec les mêmes Providers / routes que l'application.
Widget testApp(Widget home, {String lang = 'fr', GlobalKey<NavigatorState>? navigatorKey}) {
  final l10n = L10n(lang);
  final auth = AuthProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: l10n),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider(create: (_) => ChatProvider(auth)),
      ChangeNotifierProvider.value(value: FirestoreService.network),
    ],
    child: L10nScope(
      l10n: l10n,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        routes: AppRoutes.routes,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        onUnknownRoute: AppRoutes.onUnknownRoute,
        home: home,
      ),
    ),
  );
}
