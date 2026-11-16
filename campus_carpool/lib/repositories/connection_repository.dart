import 'dart:math';
import '../models.dart';
import '../services/routing_service.dart';
import 'ride_repository.dart';

/// Itinéraires avec une correspondance : quand aucun covoiturage direct n'existe entre deux villes,
/// on cherche deux trajets qui s'enchaînent (Sousse → Nabeul puis Nabeul → Tunis).
///
/// Deux trajets forment une correspondance si :
///  - le premier part du lieu de départ demandé et le second arrive à la destination demandée ;
///  - l'arrivée du premier et le départ du second sont au même endroit (même nom, ou à moins de 5 km) ;
///  - le second part au moins [minTransfer] (10 min) après l'arrivée estimée du premier,
///    et au plus [maxWait] après, pour ne pas attendre des heures.
class ConnectionRepository {
  /// Battement minimum pour changer de voiture.
  static const minTransfer = Duration(minutes: 10);

  /// Attente maximum au lieu de correspondance.
  static const maxWait = Duration(hours: 3);

  static const maxResults = 5;

  /// Distance maximum entre l'arrivée du premier trajet et le départ du second.
  static const maxStopDistanceKm = 5.0;

  /// Durées de trajet déjà calculées (par id de trajet).
  static final _durations = <String, Duration?>{};

  static Future<List<RideConnection>> find({
    required String from,
    required String to,
    String? date,
    double? maxPrice,
    int? minSeats,
  }) async {
    final seats = {if (minSeats != null) 'minSeats': '$minSeats'};
    // Premiers trajets : ils partent du départ demandé (le jour choisi, s'il y en a un)
    final firsts = await RideRepository.search({'from': from, if (date != null) 'date': date, ...seats});
    if (firsts.isEmpty) return const [];
    // Seconds trajets : ils arrivent à la destination demandée
    final seconds = await RideRepository.search({'destination': to, ...seats});

    final found = <RideConnection>[];
    for (final a in firsts) {
      if (_contains(a.to, to)) continue; // trajet direct : déjà dans la recherche normale
      for (final b in seconds) {
        if (a.id == b.id || _contains(b.from, from) || !sameStop(a, b)) continue;
        if (maxPrice != null && a.price + b.price > maxPrice) continue;
        if (!b.dateTime.isAfter(a.dateTime.add(minTransfer))) continue; // évite un calcul de durée inutile
        final duration = await rideDuration(a);
        if (duration == null) continue; // durée inconnue : on ne peut pas garantir la correspondance
        final connection = RideConnection(a, b, a.dateTime.add(duration));
        if (connection.wait >= minTransfer && connection.wait <= maxWait) found.add(connection);
      }
    }
    // Les départs les plus proches d'abord ; à départ égal, la plus courte attente
    found.sort((x, y) {
      final byDeparture = x.first.dateTime.compareTo(y.first.dateTime);
      return byDeparture != 0 ? byDeparture : x.wait.compareTo(y.wait);
    });
    return found.take(maxResults).toList();
  }

  /// Les deux trajets se rejoignent-ils au même endroit ?
  /// Même nom de lieu (« Nabeul » / « Nabeul centre »), ou coordonnées à moins de 5 km.
  static bool sameStop(Ride a, Ride b) {
    final stop = _norm(a.to), start = _norm(b.from);
    if (stop.length >= 3 && start.length >= 3 && (stop.contains(start) || start.contains(stop))) return true;
    if (a.toLat == null || a.toLng == null || b.fromLat == null || b.fromLng == null) return false;
    return distanceKm(a.toLat!, a.toLng!, b.fromLat!, b.fromLng!) <= maxStopDistanceKm;
  }

  /// Durée d'un trajet : itinéraire routier réel (OSRM) ; si le service ne répond pas, estimation
  /// à partir de la distance. Null si le trajet n'a pas de coordonnées.
  static Future<Duration?> rideDuration(Ride r) async {
    if (_durations.containsKey(r.id)) return _durations[r.id];
    Duration? duration;
    if (r.fromLat != null && r.fromLng != null && r.toLat != null && r.toLng != null) {
      try {
        final route = await RoutingService.drivingRoute((r.fromLat!, r.fromLng!), (r.toLat!, r.toLng!))
            .timeout(const Duration(seconds: 4));
        duration = Duration(minutes: route.minutes);
      } catch (_) {
        duration = estimateDuration(distanceKm(r.fromLat!, r.fromLng!, r.toLat!, r.toLng!));
      }
    }
    return _durations[r.id] = duration;
  }

  /// Estimation sans réseau : la route fait environ 1,3 fois la distance à vol d'oiseau,
  /// parcourue à 70 km/h de moyenne ; arrondie aux 5 minutes supérieures.
  static Duration estimateDuration(double straightKm) {
    final minutes = straightKm * 1.3 / 70 * 60;
    return Duration(minutes: max(5, (minutes / 5).ceil() * 5));
  }

  /// Distance à vol d'oiseau entre deux points (formule de haversine), en km.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final h = pow(sin(dLat / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
    return 6371 * 2 * asin(sqrt(h));
  }

  /// Oublie les durées calculées (tests).
  static void clearCache() => _durations.clear();

  static String _norm(String s) => s.trim().toLowerCase();
  static bool _contains(String place, String query) => _norm(place).contains(_norm(query));
}
