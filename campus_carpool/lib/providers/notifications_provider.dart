import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../l10n.dart';
import '../models.dart';
import 'auth_provider.dart';
import '../repositories/notification_repository.dart';
import '../repositories/user_repository.dart';
import '../services/firestore_service.dart';
import '../widgets.dart' show fmtPrice;

/// Notifications (Provider), en temps réel avec Firestore :
/// - l'app écoute la collection `notifications` de l'utilisateur : le badge de la cloche
///   se met à jour instantanément, et une notification Android s'affiche quand l'app est ouverte ;
/// - app en arrière-plan ou fermée : le petit serveur `push-server` envoie une vraie
///   notification push (Firebase Cloud Messaging) grâce au jeton enregistré ici.
class NotificationsProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AuthProvider auth;
  final L10n l10n;

  /// false dans les tests (pas de Firebase Messaging ni de notifications système).
  final bool enablePush;

  NotificationsProvider(this.auth, this.l10n, {this.enablePush = true});

  int _unread = 0;
  int get unread => _unread;

  /// Appelé quand l'utilisateur touche une notification (id du trajet).
  void Function(String rideId)? onOpenRide;

  /// Appelé quand l'utilisateur touche la notification d'un message (id de la réservation).
  void Function(String bookingId)? onOpenChat;

  final _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  StreamSubscription? _sub, _tokenSub, _openSub;
  bool _wasLoggedIn = false;
  bool _firstSnapshot = true;
  bool _inForeground = true;
  String? _token;

  static const channelId = 'carpool_activity';

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (enablePush && _android) {
      try {
        await _local.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
          onDidReceiveNotificationResponse: (r) {
            final id = r.payload;
            if (id != null && id.isNotEmpty) onOpenRide?.call(id);
          },
        );
        // Le même canal sert aux notifications push du serveur (même son, même importance)
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(AndroidNotificationChannel(
              channelId,
              l10n.tr('notif_channel'),
              description: l10n.tr('notif_channel_desc'),
              importance: Importance.high,
            ));
        _localReady = true;
        // Toucher une notification push (app en arrière-plan) ouvre le trajet
        _openSub = FirebaseMessaging.onMessageOpenedApp.listen(_openFromPush);
      } catch (e) {
        debugPrint('Notifications indisponibles : $e');
      }
    }
    auth.addListener(_onAuthChange);
    _onAuthChange();
  }

  /// Notification qui a lancé l'app alors qu'elle était fermée : trajet ou conversation à ouvrir.
  Future<PushTarget?> launchTarget() async {
    if (!enablePush || !_android) return null;
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      final t = m == null ? null : PushTarget.fromData(m.data);
      if (t != null) return t;
      final d = await _local.getNotificationAppLaunchDetails();
      final id = (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse?.payload : null;
      return id == null || id.isEmpty ? null : PushTarget(id);
    } catch (_) {
      return null;
    }
  }

  void open(PushTarget t) => t.chat ? onOpenChat?.call(t.id) : onOpenRide?.call(t.id);

  void _openFromPush(RemoteMessage m) {
    final t = PushTarget.fromData(m.data);
    if (t != null) open(t);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  void _onAuthChange() {
    if (auth.loggedIn == _wasLoggedIn) return;
    _wasLoggedIn = auth.loggedIn;
    _sub?.cancel();
    if (auth.loggedIn) {
      _firstSnapshot = true;
      _sub =
          NotificationRepository.myQuery().snapshots(includeMetadataChanges: true).listen(_onSnapshot, onError: (_) {});
      _registerPushToken();
      auth.beforeLogout = _unregisterPushToken;
    } else {
      _setUnread(0);
    }
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    FirestoreService.network.set(!snap.metadata.isFromCache);
    _setUnread(snap.docs.where((d) => d.data()['read'] != true).length);
    // Les notifications déjà là au démarrage ne sont pas réaffichées
    if (_firstSnapshot) {
      _firstSnapshot = false;
      return;
    }
    final added = snap.docChanges.where((c) => c.type == DocumentChangeType.added && !c.doc.metadata.hasPendingWrites);
    for (final c in added) {
      final n = NotificationRepository.fromDoc(c.doc);
      if (n.type == 'review') auth.refresh(); // nouvelle note
      // En arrière-plan, c'est la notification push du serveur qui s'affiche (pas de doublon)
      if (_inForeground) _show(n);
    }
  }

  void _setUnread(int n) {
    if (n == _unread) return;
    _unread = n;
    notifyListeners();
  }

  /// Les notifications arrivent en direct ; ceci revérifie seulement la connexion
  /// (bouton "Réessayer" de la bannière hors ligne, retour au premier plan).
  Future<void> refresh() async {
    if (!auth.loggedIn) return;
    try {
      await NotificationRepository.list(); // met à jour FirestoreService.network (en ligne / hors ligne)
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    _setUnread(0);
    try {
      await NotificationRepository.markAllRead();
    } catch (_) {}
  }

  // ---------- Jeton Firebase Cloud Messaging (push) ----------

  Future<void> _registerPushToken() async {
    if (!enablePush || !_android) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(); // Android 13+ : autorisation demandée une fois
      // Jeton FCM classique : c'est la cible attendue par firebase-admin (push-server).
      // ignore: deprecated_member_use
      _token = await fm.getToken();
      if (_token != null) await UserRepository.setField('fcmTokens', FieldValue.arrayUnion([_token]));
      await UserRepository.setField('lang', l10n.lang);
      _tokenSub?.cancel();
      // ignore: deprecated_member_use
      _tokenSub = fm.onTokenRefresh.listen((t) async {
        _token = t;
        await UserRepository.setField('fcmTokens', FieldValue.arrayUnion([t]));
      });
    } catch (e) {
      debugPrint('Push indisponible : $e');
    }
  }

  /// À la déconnexion : cet appareil ne reçoit plus les notifications de ce compte.
  Future<void> _unregisterPushToken() async {
    _tokenSub?.cancel();
    if (_token != null) await UserRepository.setField('fcmTokens', FieldValue.arrayRemove([_token]));
    _token = null;
  }

  /// Langue du compte, utilisée par le serveur pour écrire les notifications push.
  Future<void> syncLanguage() async {
    if (!auth.loggedIn) return;
    try {
      await UserRepository.setField('lang', l10n.lang);
    } catch (_) {}
  }

  Future<void> _show(AppNotification n) async {
    if (!_localReady) return;
    await _local.show(
      id: n.id.hashCode & 0x7fffffff,
      title: notifTitle(n, l10n),
      body: notifBody(n, l10n),
      payload: n.rideId,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
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
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _tokenSub?.cancel();
    _openSub?.cancel();
    auth.removeListener(_onAuthChange);
    super.dispose();
  }
}

/// Ce qu'ouvre une notification push : un trajet, ou une conversation (message).
class PushTarget {
  final String id;
  final bool chat;
  const PushTarget(this.id, {this.chat = false});

  static PushTarget? fromData(Map<String, dynamic> data) {
    final booking = data['bookingId'], ride = data['rideId'];
    if (data['type'] == 'message' && booking is String && booking.isNotEmpty) return PushTarget(booking, chat: true);
    if (ride is String && ride.isNotEmpty) return PushTarget(ride);
    return null;
  }
}

// ---------- Texte et apparence d'une notification ----------

/// Titre dans la langue choisie.
String notifTitle(AppNotification n, L10n l10n) {
  final key = 'notif_${n.type}_title';
  final t = l10n.tr(key);
  return t == key ? n.title : t;
}

String notifBody(AppNotification n, L10n l10n) {
  if (n.data.isEmpty) return n.body;
  final count = (n.data['count'] as num?)?.toInt() ?? 1;
  // Alerte sur un trajet régulier : « … 12 fois à partir du … »
  final key = n.type == 'ride_alert' && count > 1 ? 'notif_ride_alert_series_body' : 'notif_${n.type}_body';
  final t = l10n.tr(key, {
    'name': n.data['name'] ?? '',
    'route': '${n.data['from']} → ${n.data['to']}',
    'date': n.data['date'] ?? '',
    'time': n.data['time'] ?? '',
    'stars': n.data['stars'] ?? '',
    'price': n.data['price'] is num ? fmtPrice((n.data['price'] as num).toDouble()) : '',
    'count': count,
  });
  return t == key ? n.body : t;
}

IconData notifIcon(String type) => switch (type) {
      'booking_new' => Icons.person_add_alt_1,
      'booking_accepted' => Icons.check_circle,
      'ride_ended' => Icons.flag,
      'booking_declined' => Icons.cancel,
      'booking_cancelled' || 'ride_cancelled' => Icons.event_busy,
      'review' => Icons.star,
      'ride_alert' => Icons.notifications_active,
      _ => Icons.notifications,
    };

Color notifColor(String type) => switch (type) {
      'booking_accepted' => Colors.green,
      'ride_ended' => Colors.green,
      'booking_declined' || 'booking_cancelled' || 'ride_cancelled' => Colors.red,
      'review' => Colors.amber,
      'ride_alert' => Colors.deepPurple,
      _ => const Color(0xFF3F51B5),
    };
