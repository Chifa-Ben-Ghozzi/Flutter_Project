import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Erreur renvoyée par le serveur (message en français, traduit par L10n.trServer).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Serveur injoignable (pas de réseau, serveur arrêté, délai dépassé).
class NetworkException implements Exception {}

/// En ligne / hors ligne : affiché par la bannière de l'écran d'accueil.
class NetworkStatus extends ChangeNotifier {
  bool _online = true;
  bool get online => _online;
  void set(bool v) {
    if (v == _online) return;
    _online = v;
    notifyListeners();
  }
}

/// Toutes les requêtes HTTP vers le backend Node/Express (package http).
class Api {
  // Web -> même machine que la page ; Android -> IP du PC (ou 127.0.0.1 avec "adb reverse") ;
  // desktop -> localhost. Changer l'IP avec : flutter run --dart-define=API_HOST=192.168.x.x
  static String base = kIsWeb
      ? 'http://${Uri.base.host}:3000'
      : defaultTargetPlatform == TargetPlatform.android
          ? 'http://${const String.fromEnvironment('API_HOST', defaultValue: '192.168.1.2')}:3000'
          : 'http://localhost:3000';

  /// Remplaçable dans les tests par un MockClient (package:http/testing.dart).
  static http.Client client = http.Client();
  static const timeout = Duration(seconds: 10);

  static String? token;
  static final network = NetworkStatus();

  /// Appelé quand le serveur répond 401 (session expirée) -> déconnexion.
  static VoidCallback? onUnauthorized;

  static const _cachePrefix = 'cache:';

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
  }

  static Future<void> saveToken(String? t) async {
    token = t;
    final prefs = await SharedPreferences.getInstance();
    if (t == null) {
      await prefs.remove('token');
      // Oublie les données en cache de l'ancien compte
      for (final k in prefs.getKeys().where((k) => k.startsWith(_cachePrefix)).toList()) {
        await prefs.remove(k);
      }
    } else {
      await prefs.setString('token', t);
    }
  }

  /// Requête générique. Si [cache] est vrai, la réponse est gardée sur le téléphone
  /// et réutilisée quand le serveur est injoignable (mode hors ligne).
  static Future<dynamic> _req(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query, bool cache = false}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final cacheKey = '$_cachePrefix$uri';
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    late http.Response r;
    try {
      final enc = jsonEncode(body ?? {});
      final Future<http.Response> f = switch (method) {
        'GET' => client.get(uri, headers: headers),
        'PUT' => client.put(uri, headers: headers, body: enc),
        _ => client.post(uri, headers: headers, body: enc),
      };
      r = await f.timeout(timeout);
    } catch (_) {
      network.set(false);
      if (cache) {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(cacheKey);
        if (saved != null) return jsonDecode(saved);
      }
      throw NetworkException();
    }
    network.set(true);
    final data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      if (r.statusCode == 401 && token != null) onUnauthorized?.call();
      throw ApiException(data is Map && data['error'] != null ? data['error'] : 'Erreur ${r.statusCode}');
    }
    if (cache) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(data));
    }
    return data;
  }

  static Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d);
  static List<T> _list<T>(dynamic d, T Function(Map<String, dynamic>) f) =>
      (d as List).map((e) => f(_map(e))).toList();

  // ---------- Compte ----------
  /// Renvoie {token, user}.
  static Future<(String, AppUser)> login(String email, String password) async {
    final d = await _req('POST', '/auth/login', body: {'email': email, 'password': password});
    return (d['token'] as String, AppUser.fromJson(_map(d['user'])));
  }

  static Future<(String, AppUser)> register(String email, String password, String name) async {
    final d = await _req('POST', '/auth/register', body: {'email': email, 'password': password, 'name': name});
    return (d['token'] as String, AppUser.fromJson(_map(d['user'])));
  }

  static Future<AppUser> me() async => AppUser.fromJson(_map(await _req('GET', '/me', cache: true)));

  static Future<AppUser> updateProfile(Map<String, dynamic> body) async =>
      AppUser.fromJson(_map(await _req('PUT', '/me', body: body)));

  static Future<AppUser> publicUser(String id) async => AppUser.fromJson(_map(await _req('GET', '/users/$id')));

  // ---------- Trajets ----------
  static Future<List<Ride>> searchRides(Map<String, String> q) async =>
      _list(await _req('GET', '/rides', query: q, cache: true), Ride.fromJson);
  static Future<void> postRide(Map<String, dynamic> b) => _req('POST', '/rides', body: b);
  static Future<List<Ride>> myRides() async => _list(await _req('GET', '/rides/mine', cache: true), Ride.fromJson);
  static Future<RideDetails> rideDetails(String id) async =>
      RideDetails.fromJson(_map(await _req('GET', '/rides/$id', cache: true)));
  static Future<void> cancelRide(String id) => _req('POST', '/rides/$id/cancel');

  // ---------- Réservations ----------
  static Future<void> book(String rideId) => _req('POST', '/rides/$rideId/book');
  static Future<List<Booking>> myBookings() async =>
      _list(await _req('GET', '/bookings/mine', cache: true), Booking.fromJson);
  static Future<void> respond(String id, bool accept) =>
      _req('POST', '/bookings/$id/respond', body: {'accept': accept});
  static Future<void> cancelBooking(String id) => _req('POST', '/bookings/$id/cancel');

  // ---------- Avis ----------
  static Future<void> review(String rideId, String toId, int stars, String comment) =>
      _req('POST', '/rides/$rideId/review', body: {'toId': toId, 'stars': stars, 'comment': comment});

  // ---------- Notifications ----------
  static Future<List<AppNotification>> notifications() async =>
      _list(await _req('GET', '/notifications', cache: true), AppNotification.fromJson);

  /// {unread, fresh} : nombre de non lues + nouvelles notifications à afficher.
  static Future<(int, List<AppNotification>)> pollNotifications() async {
    final d = await _req('GET', '/notifications/poll');
    return (d['unread'] as int? ?? 0, _list(d['fresh'] ?? [], AppNotification.fromJson));
  }

  static Future<void> markNotificationsRead() => _req('POST', '/notifications/read');
}
