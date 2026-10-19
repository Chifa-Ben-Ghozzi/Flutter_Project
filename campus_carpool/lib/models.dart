/// Modèles typés : chaque réponse JSON de l'API est convertie en objet Dart (fromJson).
/// Avantages : autocomplétion, erreurs détectées à la compilation, code plus lisible
/// (ride.price au lieu de ride['price']).
library;

double? _toDouble(dynamic v) => v == null ? null : (v as num).toDouble();
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? []).map((e) => f(Map<String, dynamic>.from(e))).toList();

class AppUser {
  final String id;
  final String name;
  final String? email; // seulement pour l'utilisateur connecté
  final String phone;
  final String carModel;
  final String carPlate;
  final String? photo; // image en base64
  final double? rating; // null = pas encore d'avis
  final int ratingCount;
  final List<Review> reviews; // seulement dans le profil public

  const AppUser({
    required this.id,
    required this.name,
    this.email,
    this.phone = '',
    this.carModel = '',
    this.carPlate = '',
    this.photo,
    this.rating,
    this.ratingCount = 0,
    this.reviews = const [],
  });

  bool get hasCar => carModel.isNotEmpty;
  bool get hasPhone => phone.trim().isNotEmpty;
  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final car = Map<String, dynamic>.from(j['car'] ?? const {});
    return AppUser(
      id: j['id'] ?? '',
      name: j['name'] ?? '',
      email: j['email'],
      phone: j['phone'] ?? '',
      carModel: car['model'] ?? '',
      carPlate: car['plate'] ?? '',
      photo: j['photo'],
      rating: _toDouble(j['rating']),
      ratingCount: j['ratingCount'] ?? 0,
      reviews: _list(j['reviews'], Review.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'car': {'model': carModel, 'plate': carPlate},
        'photo': photo,
        'rating': rating,
        'ratingCount': ratingCount,
      };
}

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
  final String status; // open | cancelled
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
        price: _toDouble(j['price']) ?? 0,
        status: j['status'] ?? 'open',
        driver: j['driver'] == null ? null : AppUser.fromJson(Map<String, dynamic>.from(j['driver'])),
        myBookingStatus: j['myBooking'] is String ? j['myBooking'] : null,
        bookings: _list(j['bookings'], Booking.fromJson),
        fromLat: _toDouble(j['fromLat']),
        fromLng: _toDouble(j['fromLng']),
        toLat: _toDouble(j['toLat']),
        toLng: _toDouble(j['toLng']),
      );
}

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
  bool get isUpcoming => isActive && ride != null && !ride!.isPast;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'],
        rideId: j['rideId'] ?? '',
        passengerId: j['passengerId'] ?? '',
        status: j['status'] ?? 'pending',
        createdAt: j['createdAt'] ?? '',
        passenger: j['passenger'] == null ? null : AppUser.fromJson(Map<String, dynamic>.from(j['passenger'])),
        ride: j['ride'] == null ? null : Ride.fromJson(Map<String, dynamic>.from(j['ride'])),
      );
}

/// Réponse de GET /rides/:id : le trajet + ce que l'utilisateur connecté peut faire.
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
        myBooking: j['myBooking'] == null ? null : Booking.fromJson(Map<String, dynamic>.from(j['myBooking'])),
        toRate: _list(j['toRate'], AppUser.fromJson),
      );
}

class Review {
  final String id;
  final int stars;
  final String comment;
  final String from; // nom de l'auteur
  final String createdAt;

  const Review({required this.id, required this.stars, this.comment = '', this.from = '', this.createdAt = ''});

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: j['id'] ?? '',
        stars: (j['stars'] as num?)?.toInt() ?? 0,
        comment: j['comment'] ?? '',
        from: j['from'] ?? '',
        createdAt: j['createdAt'] ?? '',
      );
}

class AppNotification {
  final String id;
  final String type;
  final String title; // texte français du serveur (secours)
  final String body;
  final String? rideId;
  final bool read;
  final String createdAt;
  final Map<String, dynamic> data; // nom, trajet, date… pour traduire

  const AppNotification({
    required this.id,
    required this.type,
    this.title = '',
    this.body = '',
    this.rideId,
    this.read = false,
    this.createdAt = '',
    this.data = const {},
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'],
        type: j['type'] ?? '',
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        rideId: j['rideId'],
        read: j['read'] ?? false,
        createdAt: j['createdAt'] ?? '',
        data: Map<String, dynamic>.from(j['data'] ?? const {}),
      );
}

/// Statistiques du profil (calculées dans l'app).
class ProfileStats {
  final int ridesAsDriver;
  final int ridesAsPassenger;
  final int seatsShared;
  final int upcoming;

  const ProfileStats({this.ridesAsDriver = 0, this.ridesAsPassenger = 0, this.seatsShared = 0, this.upcoming = 0});

  factory ProfileStats.compute(List<Ride> myRides, List<Booking> myBookings) {
    final done = myRides.where((r) => !r.isCancelled && r.isPast);
    return ProfileStats(
      ridesAsDriver: done.length,
      ridesAsPassenger: myBookings.where((b) => b.status == 'accepted' && b.ride != null && b.ride!.isPast).length,
      seatsShared: done.fold(0, (s, r) => s + r.seats - r.seatsLeft),
      upcoming: myRides.where((r) => r.isUpcoming).length + myBookings.where((b) => b.isUpcoming).length,
    );
  }
}
