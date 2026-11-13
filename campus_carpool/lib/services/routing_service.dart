import 'dart:convert';
import 'http_service.dart';

/// Itinéraire routier calculé par OSRM.
class RouteInfo {
  final List<(double, double)> path; // points (latitude, longitude)
  final double km;
  final int minutes;
  const RouteInfo(this.path, this.km, this.minutes);
}

/// Itinéraire routier avec le service gratuit OSRM (distance, durée, tracé).
class RoutingService {
  /// Itinéraire en voiture entre deux points ; lève une exception si le service ne répond pas.
  static Future<RouteInfo> drivingRoute((double, double) from, (double, double) to) async {
    final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '${from.$2},${from.$1};${to.$2},${to.$1}?overview=full&geometries=geojson');
    final r = await HttpService.client.get(url).timeout(const Duration(seconds: 8));
    final route = (jsonDecode(r.body)['routes'] as List).first;
    final coords = route['geometry']['coordinates'] as List;
    return RouteInfo(
      coords.map((c) => ((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList(),
      (route['distance'] as num) / 1000,
      ((route['duration'] as num) / 60).round(),
    );
  }
}
