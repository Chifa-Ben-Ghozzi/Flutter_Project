import 'package:flutter/material.dart';
import 'l10n.dart';
import 'screens/notifications_screen.dart';
import 'screens/ride_details_screen.dart';

/// Routes nommées de l'application.
/// - Sans paramètre      : déclarées dans [AppRoutes.routes] (table `routes:` du MaterialApp)
/// - Avec des arguments  : construites par [AppRoutes.onGenerateRoute]
///
/// Exemples :
///   Navigator.pushNamed(context, AppRoutes.notifications);
///   Navigator.pushNamed(context, AppRoutes.rideDetails, arguments: rideId);
class AppRoutes {
  static const notifications = '/notifications';
  static const rideDetails = '/ride';

  static final Map<String, WidgetBuilder> routes = {
    notifications: (_) => const NotificationsScreen(),
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case rideDetails:
        final rideId = settings.arguments as String; // argument passé par pushNamed
        return MaterialPageRoute<bool>(
          settings: settings,
          builder: (_) => RideDetailsScreen(rideId: rideId),
        );
    }
    return null; // route inconnue -> onUnknownRoute
  }

  static Route<dynamic> onUnknownRoute(RouteSettings settings) => MaterialPageRoute(
        settings: settings,
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(context.tr('page_not_found'))),
          body: Center(child: Text(context.tr('no_page_for', {'name': settings.name}))),
        ),
      );
}
