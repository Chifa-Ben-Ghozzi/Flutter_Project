import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'http_service.dart';

/// Géocodage avec OpenStreetMap Nominatim (gratuit) : "Ariana" -> coordonnées pour la carte.
class GeocodingService {
  /// Coordonnées du départ et de l'arrivée, ou null si le service ne répond pas.
  static Future<Map<String, double>?> geocodeRoute(String from, String to) async {
    final a = await geocode(from);
    final b = await geocode(to);
    if (a == null || b == null) return null;
    return {'fromLat': a.$1, 'fromLng': a.$2, 'toLat': b.$1, 'toLng': b.$2};
  }

  /// (latitude, longitude) d'un lieu : d'abord en Tunisie, puis partout ; null si introuvable.
  static Future<(double, double)?> geocode(String place) async {
    Future<(double, double)?> search(String extra) async {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&limit=1$extra'
          '&q=${Uri.encodeQueryComponent(place)}');
      final r = await HttpService.client
          .get(url, headers: kIsWeb ? null : {'User-Agent': 'CampusCarpool/1.0 (student project)'})
          .timeout(const Duration(seconds: 6));
      final list = jsonDecode(r.body) as List;
      if (list.isEmpty) return null;
      return (double.parse(list.first['lat']), double.parse(list.first['lon']));
    }

    try {
      return await search('&countrycodes=tn') ?? await search('');
    } catch (_) {
      return null; // pas de carte pour ce trajet
    }
  }
}
