import 'json_utils.dart';
import 'ride.dart';

/// Une alerte de trajet : « préviens-moi quand quelqu'un publie un trajet Ariana → Esprit à 5 dt max ».
/// Un champ vide veut dire « n'importe où ».
class RideAlert {
  final String id;
  final String userId;
  final String from;
  final String to;
  final double? maxPrice;

  const RideAlert({required this.id, required this.userId, this.from = '', this.to = '', this.maxPrice});

  /// Le trajet correspond-il à l'alerte ? (même règle que la recherche : texte contenu, sans tenir compte des majuscules)
  bool matches(Ride r) =>
      (from.isEmpty || _norm(r.from).contains(_norm(from))) &&
      (to.isEmpty || _norm(r.to).contains(_norm(to))) &&
      (maxPrice == null || r.price <= maxPrice!);

  static String _norm(String s) => s.trim().toLowerCase();

  factory RideAlert.fromJson(Map<String, dynamic> j) => RideAlert(
        id: j['id'],
        userId: j['userId'] ?? '',
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        maxPrice: toDoubleOrNull(j['maxPrice']),
      );
}
