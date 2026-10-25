import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import 'auth_provider.dart';

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

  /// Notification push qui a lancé l'app alors qu'elle était fermée.
  Future<String?> launchRideId() async {
    if (!enablePush || !_android) return null;
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      if (m?.data['rideId'] != null) return m!.data['rideId'];
      final d = await _local.getNotificationAppLaunchDetails();
      return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse?.payload : null;
    } catch (_) {
      return null;
    }
  }

  void _openFromPush(RemoteMessage m) {
    final id = m.data['rideId'];
    if (id is String && id.isNotEmpty) onOpenRide?.call(id);
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
      _sub = Api.myNotificationsQuery().snapshots(includeMetadataChanges: true).listen(_onSnapshot, onError: (_) {});
      _registerPushToken();
      auth.beforeLogout = _unregisterPushToken;
    } else {
      _setUnread(0);
    }
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    Api.network.set(!snap.metadata.isFromCache);
    _setUnread(snap.docs.where((d) => d.data()['read'] != true).length);
    // Les notifications déjà là au démarrage ne sont pas réaffichées
    if (_firstSnapshot) {
      _firstSnapshot = false;
      return;
    }
    final added = snap.docChanges.where((c) => c.type == DocumentChangeType.added && !c.doc.metadata.hasPendingWrites);
    for (final c in added) {
      final n = Api.notificationFrom(c.doc);
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
      await Api.notifications(); // met à jour Api.network (en ligne / hors ligne)
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    _setUnread(0);
    try {
      await Api.markNotificationsRead();
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
      if (_token != null) await Api.setUserField('fcmTokens', FieldValue.arrayUnion([_token]));
      await Api.setUserField('lang', l10n.lang);
      _tokenSub?.cancel();
      // ignore: deprecated_member_use
      _tokenSub = fm.onTokenRefresh.listen((t) async {
        _token = t;
        await Api.setUserField('fcmTokens', FieldValue.arrayUnion([t]));
      });
    } catch (e) {
      debugPrint('Push indisponible : $e');
    }
  }

  /// À la déconnexion : cet appareil ne reçoit plus les notifications de ce compte.
  Future<void> _unregisterPushToken() async {
    _tokenSub?.cancel();
    if (_token != null) await Api.setUserField('fcmTokens', FieldValue.arrayRemove([_token]));
    _token = null;
  }

  /// Langue du compte, utilisée par le serveur pour écrire les notifications push.
  Future<void> syncLanguage() async {
    if (!auth.loggedIn) return;
    try {
      await Api.setUserField('lang', l10n.lang);
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

// ---------- Texte et apparence d'une notification ----------

/// Titre dans la langue choisie.
String notifTitle(AppNotification n, L10n l10n) {
  final key = 'notif_${n.type}_title';
  final t = l10n.tr(key);
  return t == key ? n.title : t;
}

String notifBody(AppNotification n, L10n l10n) {
  if (n.data.isEmpty) return n.body;
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
