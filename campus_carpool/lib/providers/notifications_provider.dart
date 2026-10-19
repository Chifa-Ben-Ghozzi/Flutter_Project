import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import 'auth_provider.dart';

/// Notifications (Provider) : le serveur garde la liste, l'app la récupère toutes les 15 s.
/// - [unread] alimente le badge de la cloche
/// - chaque nouvelle notification est aussi affichée dans la barre du téléphone (Android)
/// Fonctionne quand l'app est ouverte ou en arrière-plan, pas quand elle est fermée.
class NotificationsProvider extends ChangeNotifier {
  final AuthProvider auth;
  final L10n l10n;
  NotificationsProvider(this.auth, this.l10n);

  int _unread = 0;
  int get unread => _unread;

  /// Appelé quand l'utilisateur touche une notification du téléphone (id du trajet).
  void Function(String rideId)? onOpenRide;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;
  Timer? _timer;
  bool _wasLoggedIn = false;
  static const interval = Duration(seconds: 15);

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (_supported) {
      try {
        await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
          onDidReceiveNotificationResponse: (r) {
            final id = r.payload;
            if (id != null && id.isNotEmpty) onOpenRide?.call(id);
          },
        );
        _pluginReady = true;
      } catch (e) {
        debugPrint('Notifications indisponibles : $e');
      }
    }
    auth.addListener(_onAuthChange);
    _onAuthChange();
  }

  /// Notification qui a lancé l'app (si elle était fermée).
  Future<String?> launchRideId() async {
    if (!_pluginReady) return null;
    final d = await _plugin.getNotificationAppLaunchDetails();
    return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse?.payload : null;
  }

  void _onAuthChange() {
    if (auth.loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = auth.loggedIn;
    _timer?.cancel();
    if (auth.loggedIn) {
      if (_pluginReady) {
        _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission(); // Android 13+ : autorisation demandée une fois
      }
      refresh();
      _timer = Timer.periodic(interval, (_) => refresh());
    } else {
      _setUnread(0);
    }
  }

  void _setUnread(int n) {
    if (n == _unread) return;
    _unread = n;
    notifyListeners();
  }

  /// Récupère le nombre de non lues et affiche les nouvelles sur le téléphone.
  Future<void> refresh() async {
    if (!auth.loggedIn) return;
    try {
      final (unread, fresh) = await Api.pollNotifications();
      _setUnread(unread);
      for (final n in fresh) {
        await _show(n);
      }
      if (fresh.any((n) => n.type == 'review')) auth.refresh(); // nouvelle note
    } catch (_) {
      // Serveur injoignable : on réessaiera au prochain tour
    }
  }

  Future<void> markAllRead() async {
    _setUnread(0);
    try {
      await Api.markNotificationsRead();
    } catch (_) {}
  }

  Future<void> _show(AppNotification n) async {
    if (!_pluginReady) return;
    await _plugin.show(
      id: n.id.hashCode & 0x7fffffff,
      title: notifTitle(n, l10n),
      body: notifBody(n, l10n),
      payload: n.rideId,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'carpool_activity',
          l10n.tr('notif_channel'),
          channelDescription: l10n.tr('notif_channel_desc'),
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF3F51B5),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    auth.removeListener(_onAuthChange);
    super.dispose();
  }
}

// ---------- Texte et apparence d'une notification ----------

/// Titre dans la langue choisie (texte français du serveur en secours).
String notifTitle(AppNotification n, L10n l10n) {
  final key = 'notif_${n.type}_title';
  final t = l10n.tr(key);
  return t == key ? n.title : t;
}

String notifBody(AppNotification n, L10n l10n) {
  if (n.data.isEmpty) return n.body; // anciennes notifications sans données
  final key = 'notif_${n.type}_body';
  final t = l10n.tr(key, {
    'name': n.data['name'] ?? '',
    'route': '${n.data['from']} → ${n.data['to']}',
    'date': n.data['date'] ?? '',
    'time': n.data['time'] ?? '',
    'stars': n.data['stars'] ?? '',
  });
  return t == key ? n.body : t;
}

IconData notifIcon(String type) => switch (type) {
      'booking_new' => Icons.person_add_alt_1,
      'booking_accepted' => Icons.check_circle,
      'booking_declined' => Icons.cancel,
      'booking_cancelled' || 'ride_cancelled' => Icons.event_busy,
      'review' => Icons.star,
      _ => Icons.notifications,
    };

Color notifColor(String type) => switch (type) {
      'booking_accepted' => Colors.green,
      'booking_declined' || 'booking_cancelled' || 'ride_cancelled' => Colors.red,
      'review' => Colors.amber,
      _ => const Color(0xFF3F51B5),
    };
