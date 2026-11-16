import 'ride.dart';

/// Un itinéraire avec correspondance : deux covoiturages qui s'enchaînent
/// (Sousse → Nabeul, puis Nabeul → Tunis) quand il n'existe pas de trajet direct.
class RideConnection {
  final Ride first;
  final Ride second;

  /// Heure d'arrivée estimée du premier trajet au lieu de correspondance.
  final DateTime arrival;

  const RideConnection(this.first, this.second, this.arrival);

  /// Lieu de correspondance.
  String get via => first.to;

  /// Attente entre l'arrivée du premier trajet et le départ du second.
  Duration get wait => second.dateTime.difference(arrival);

  double get price => first.price + second.price;
}
