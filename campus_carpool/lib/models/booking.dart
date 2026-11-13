import 'app_user.dart';
import 'json_utils.dart';
import 'ride.dart';

/// Une demande de place d'un passager sur un trajet.
class Booking {
  final String id;
  final String rideId;
  final String passengerId;
  final String status; // pending | accepted | declined | cancelled
  final String createdAt;
  final AppUser? passenger;
  final Ride? ride; // dans "mes réservations"

  const Booking({
    required this.id,
    required this.rideId,
    required this.passengerId,
    required this.status,
    this.createdAt = '',
    this.passenger,
    this.ride,
  });

  bool get isActive => status == 'pending' || status == 'accepted';
  bool get isUpcoming => isActive && ride != null && ride!.isUpcoming;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'],
        rideId: j['rideId'] ?? '',
        passengerId: j['passengerId'] ?? '',
        status: j['status'] ?? 'pending',
        createdAt: j['createdAt'] ?? '',
        passenger: j['passenger'] == null ? null : AppUser.fromJson(asJson(j['passenger'])),
        ride: j['ride'] == null ? null : Ride.fromJson(asJson(j['ride'])),
      );
}
