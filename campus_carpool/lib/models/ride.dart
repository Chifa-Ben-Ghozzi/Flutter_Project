import 'app_user.dart';
import 'booking.dart';
import 'json_utils.dart';

/// Un trajet proposé par un conducteur.
class Ride {
  final String id;
  final String driverId;
  final String from;
  final String to;
  final String date; // AAAA-MM-JJ
  final String time; // HH:MM
  final int seats;
  final int seatsLeft;
  final double price;
  final String status; // open | cancelled | completed
  final AppUser? driver;
  final String? myBookingStatus; // dans la recherche : statut de ma demande
  final List<Booking> bookings; // dans "mes trajets" / détails
  final double? fromLat, fromLng, toLat, toLng;

  const Ride({
    required this.id,
    required this.driverId,
    required this.from,
    required this.to,
    required this.date,
    required this.time,
    required this.seats,
    required this.seatsLeft,
    required this.price,
    required this.status,
    this.driver,
    this.myBookingStatus,
    this.bookings = const [],
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
  });

  DateTime get dateTime => DateTime.parse('${date}T$time:00');
  bool get isPast => dateTime.isBefore(DateTime.now());
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isUpcoming => status == 'open' && !isPast;
  bool get hasCoords => fromLat != null && toLat != null;
  String get route => '$from → $to';

  factory Ride.fromJson(Map<String, dynamic> j) => Ride(
        id: j['id'],
        driverId: j['driverId'] ?? '',
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        date: j['date'] ?? '',
        time: j['time'] ?? '',
        seats: (j['seats'] as num?)?.toInt() ?? 0,
        seatsLeft: (j['seatsLeft'] as num?)?.toInt() ?? 0,
        price: toDoubleOrNull(j['price']) ?? 0,
        status: j['status'] ?? 'open',
        driver: j['driver'] == null ? null : AppUser.fromJson(asJson(j['driver'])),
        myBookingStatus: j['myBooking'] is String ? j['myBooking'] : null,
        bookings: listOf(j['bookings'], Booking.fromJson),
        fromLat: toDoubleOrNull(j['fromLat']),
        fromLng: toDoubleOrNull(j['fromLng']),
        toLat: toDoubleOrNull(j['toLat']),
        toLng: toDoubleOrNull(j['toLng']),
      );
}
