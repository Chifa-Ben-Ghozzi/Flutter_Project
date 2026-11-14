import 'package:flutter/material.dart';
import 'l10n.dart';
import 'screens/alerts_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/ride_details_screen.dart';

/// Routes nommées de l'application.
/// - Sans paramètre      : déclarées dans [AppRoutes.routes] (table `routes:` du MaterialApp)
/// - Avec des arguments  : construites par [AppRoutes.onGenerateRoute]
///
/// Exemples :
///   Navigator.pushNamed(context, AppRoutes.notifications);
///   Navigator.pushNamed(context, AppRoutes.rideDetails, arguments: rideId);
///   Navigator.pushNamed(context, AppRoutes.chat, arguments: bookingId);
class AppRoutes {
  static const notifications = '/notifications';
  static const rideDetails = '/ride';
  static const messages = '/messages';
  static const chat = '/chat';
  static const alerts = '/alerts';

  static final Map<String, WidgetBuilder> routes = {
    notifications: (_) => const NotificationsScreen(),
    messages: (_) => const MessagesScreen(),
    alerts: (_) => const AlertsScreen(),
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case rideDetails:
        final rideId = settings.arguments as String; // argument passé par pushNamed
        return MaterialPageRoute<bool>(
          settings: settings,
          builder: (_) => RideDetailsScreen(rideId: rideId),
        );
      case chat:
        final bookingId = settings.arguments as String; // une conversation par réservation
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ChatScreen(bookingId: bookingId),
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
