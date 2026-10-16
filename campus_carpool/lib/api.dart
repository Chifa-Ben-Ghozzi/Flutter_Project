import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
}

class Api {
  // Émulateur Android -> 10.0.2.2 ; sinon localhost.
  // Téléphone réel : remplacez par l'IP de votre PC, ex: 'http://192.168.1.20:3000'
  // static String base = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
  //     ? 'http://10.0.2.2:3000'
  //     : 'http://localhost:3000';
  //static String base = 'http://192.168.1.126:3000';
  static String base = 'http://localhost:3000'; //added by eya so i can run the app on my phone
  static Future<void> devLogin() async {
  token = 'dev';
  user = {'id': 'dev', 'email': 'dev@univ.fr', 'name': 'Dev', 'phone': '', 'car': {'model': '', 'plate': ''}, 'photo': null};
  loggedIn.value = true;
}

  static String? token;
  static Map<String, dynamic>? user;
  static final loggedIn = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    if (token != null) {
      try {
        user = Map<String, dynamic>.from(await _req('GET', '/me'));
        loggedIn.value = true;
      } catch (_) {
        token = null;
      }
    }
  }

  static Future<dynamic> _req(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final enc = body == null ? null : jsonEncode(body);
    late http.Response r;
    if (method == 'GET') {
      r = await http.get(uri, headers: headers);
    } else if (method == 'PUT') {
      r = await http.put(uri, headers: headers, body: enc);
    } else {
      r = await http.post(uri, headers: headers, body: enc ?? '{}');
    }
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) {
      if (r.statusCode == 401 && token != null) await logout();
      throw ApiException(data?['error'] ?? 'Erreur ${r.statusCode}');
    }
    return data;
  }

  static Future<void> _saveSession(dynamic data) async {
    token = data['token'];
    user = Map<String, dynamic>.from(data['user']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    loggedIn.value = true;
  }

  static Future<void> login(String email, String password) async =>
      _saveSession(await _req('POST', '/auth/login', body: {'email': email, 'password': password}));

  static Future<void> register(String email, String password, String name) async =>
      _saveSession(await _req('POST', '/auth/register',
          body: {'email': email, 'password': password, 'name': name}));

  static Future<void> logout() async {
    token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    loggedIn.value = false;
  }

  static Future<void> updateProfile(Map<String, dynamic> body) async =>
      user = Map<String, dynamic>.from(await _req('PUT', '/me', body: body));

  static Future<List> searchRides(Map<String, String> q) async => await _req('GET', '/rides', query: q);
  static Future<void> postRide(Map<String, dynamic> b) => _req('POST', '/rides', body: b);
  static Future<List> myRides() async => await _req('GET', '/rides/mine');
  static Future<void> cancelRide(String id) => _req('POST', '/rides/$id/cancel');
  static Future<void> book(String rideId) => _req('POST', '/rides/$rideId/book');
  static Future<List> myBookings() async => await _req('GET', '/bookings/mine');
  static Future<void> respond(String id, bool accept) =>
      _req('POST', '/bookings/$id/respond', body: {'accept': accept});
  static Future<void> cancelBooking(String id) => _req('POST', '/bookings/$id/cancel');
}
