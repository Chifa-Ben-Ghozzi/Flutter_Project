import 'app_user.dart';
import 'booking.dart';
import 'json_utils.dart';
import 'ride.dart';

/// Détails d'un trajet + ce que l'utilisateur connecté peut faire (réserver, appeler, noter).
class RideDetails {
  final Ride ride;
  final bool isDriver;
  final bool finished;
  final Booking? myBooking;
  final List<AppUser> toRate;

  const RideDetails({
    required this.ride,
    required this.isDriver,
    required this.finished,
    this.myBooking,
    this.toRate = const [],
  });

  AppUser get driver => ride.driver!;
  bool get isOpen => ride.status == 'open' && !finished;
  bool get iAmAccepted => myBooking?.status == 'accepted';

  factory RideDetails.fromJson(Map<String, dynamic> j) => RideDetails(
        ride: Ride.fromJson(j),
        isDriver: j['isDriver'] ?? false,
        finished: j['finished'] ?? false,
        myBooking: j['myBooking'] == null ? null : Booking.fromJson(asJson(j['myBooking'])),
        toRate: listOf(j['toRate'], AppUser.fromJson),
      );
}
