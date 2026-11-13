import 'booking.dart';
import 'ride.dart';

/// Statistiques du profil (calculées dans l'app).
class ProfileStats {
  final int ridesAsDriver;
  final int ridesAsPassenger;
  final int seatsShared;
  final int upcoming;

  const ProfileStats({this.ridesAsDriver = 0, this.ridesAsPassenger = 0, this.seatsShared = 0, this.upcoming = 0});

  factory ProfileStats.compute(List<Ride> myRides, List<Booking> myBookings) {
    final done = myRides.where((r) => !r.isCancelled && (r.isCompleted || r.isPast));
    return ProfileStats(
      ridesAsDriver: done.length,
      ridesAsPassenger: myBookings
          .where((b) => b.status == 'accepted' && b.ride != null && (b.ride!.isCompleted || b.ride!.isPast))
          .length,
      seatsShared: done.fold(0, (s, r) => s + r.seats - r.seatsLeft),
      upcoming: myRides.where((r) => r.isUpcoming).length + myBookings.where((b) => b.isUpcoming).length,
    );
  }
}
