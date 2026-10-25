import 'package:campus_carpool/api.dart';
import 'package:campus_carpool/l10n.dart';
import 'package:campus_carpool/providers/auth_provider.dart';
import 'package:campus_carpool/providers/settings_provider.dart';
import 'package:campus_carpool/routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Monte un écran avec les mêmes Providers / routes que l'application.
Widget testApp(Widget home, {String lang = 'fr', GlobalKey<NavigatorState>? navigatorKey}) {
  final l10n = L10n(lang);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: l10n),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider.value(value: Api.network),
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
