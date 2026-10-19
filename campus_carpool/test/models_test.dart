import 'package:campus_carpool/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> rideJson({String date = '2099-01-01', String status = 'open', int seats = 3, int left = 2}) => {
      'id': 'r1',
      'driverId': 'u1',
      'from': 'Ariana',
      'to': 'Esprit',
      'date': date,
      'time': '08:30',
      'seats': seats,
      'seatsLeft': left,
      'price': 4, // entier dans le JSON -> double dans le modèle
      'status': status,
      'driver': {
        'id': 'u1',
        'name': 'Amira',
        'phone': '22123456',
        'car': {'model': 'Clio', 'plate': '215 TU 1'},
        'rating': 4.5,
        'ratingCount': 2,
      },
      'fromLat': 36.86,
      'fromLng': 10.19,
      'toLat': 36.89,
      'toLng': 10.18,
    };

void main() {
  test('Ride.fromJson convertit les types et calcule les propriétés', () {
    final r = Ride.fromJson(rideJson());
    expect(r.price, 4.0);
    expect(r.route, 'Ariana → Esprit');
    expect(r.dateTime, DateTime(2099, 1, 1, 8, 30));
    expect(r.isUpcoming, isTrue);
    expect(r.hasCoords, isTrue);
    expect(r.driver!.name, 'Amira');
    expect(r.driver!.hasCar, isTrue);
    expect(r.driver!.rating, 4.5);
  });

  test('trajet passé ou annulé : plus "à venir"', () {
    expect(Ride.fromJson(rideJson(date: '2000-01-01')).isUpcoming, isFalse);
    expect(Ride.fromJson(rideJson(status: 'cancelled')).isUpcoming, isFalse);
  });

  test('myBooking : statut (recherche) ou objet (détails)', () {
    final search = Ride.fromJson({...rideJson(), 'myBooking': 'pending'});
    expect(search.myBookingStatus, 'pending');

    final details = RideDetails.fromJson({
      ...rideJson(),
      'isDriver': false,
      'finished': false,
      'myBooking': {'id': 'b1', 'rideId': 'r1', 'passengerId': 'me', 'status': 'accepted'},
      'toRate': [],
    });
    expect(details.ride.myBookingStatus, isNull);
    expect(details.iAmAccepted, isTrue);
    expect(details.isOpen, isTrue);
  });

  test('AppUser sans note ni voiture', () {
    final u = AppUser.fromJson({'id': 'x', 'name': 'sami'});
    expect(u.rating, isNull);
    expect(u.hasCar, isFalse);
    expect(u.hasPhone, isFalse);
    expect(u.initial, 'S');
  });

  test('ProfileStats compte trajets, places et réservations', () {
    final past = Ride.fromJson(rideJson(date: '2000-01-01', seats: 3, left: 1)); // 2 places prises
    final future = Ride.fromJson(rideJson());
    final cancelled = Ride.fromJson(rideJson(date: '2000-01-01', status: 'cancelled'));
    final bookings = [
      Booking.fromJson({'id': 'b1', 'rideId': 'r', 'passengerId': 'me', 'status': 'accepted', 'ride': rideJson(date: '2000-01-01')}),
      Booking.fromJson({'id': 'b2', 'rideId': 'r', 'passengerId': 'me', 'status': 'pending', 'ride': rideJson()}),
    ];
    final s = ProfileStats.compute([past, future, cancelled], bookings);
    expect(s.ridesAsDriver, 1);
    expect(s.seatsShared, 2);
    expect(s.ridesAsPassenger, 1);
    expect(s.upcoming, 2); // 1 trajet à venir + 1 réservation à venir
  });

  test('AppNotification garde les données pour la traduction', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'type': 'review',
      'rideId': 'r1',
      'data': {'name': 'Sami', 'stars': 5},
    });
    expect(n.read, isFalse);
    expect(n.data['stars'], 5);
  });
}
