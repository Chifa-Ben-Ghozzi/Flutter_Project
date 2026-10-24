import 'package:campus_carpool/api.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Base Firestore en mémoire avec 3 utilisateurs et 2 trajets d'Amira (un à venir, un passé).
/// Api utilise cette base ; le géocodage renvoie "aucun résultat" (pas de réseau dans les tests).
Future<FakeFirebaseFirestore> fakeDb() async {
  final db = FakeFirebaseFirestore();
  Api.db = db;
  Api.client = MockClient((_) async => http.Response('[]', 200));

  Future<void> user(String id, String name, {String phone = '', String car = '', num sum = 0, int count = 0}) =>
      db.doc('users/$id').set({
        'email': '$id@esprit.univ.tn',
        'name': name,
        'phone': phone,
        'carModel': car,
        'carPlate': car.isEmpty ? '' : '215 TU 1',
        'photo': null,
        'ratingSum': sum,
        'ratingCount': count,
        'fcmTokens': <String>[],
      });
  await user('amira', 'Amira', phone: '22123456', car: 'Clio', sum: 9, count: 2);
  await user('demo', 'Demo', phone: '22111222');
  await user('sarra', 'Sarra');

  Future<void> ride(String id, String date, {int seats = 3, num price = 4}) => db.doc('rides/$id').set({
        'driverId': 'amira',
        'from': 'Ariana',
        'to': 'Esprit Ghazela',
        'date': date,
        'time': '08:30',
        'dateTime': Timestamp.fromDate(DateTime.parse('${date}T08:30:00')),
        'seats': seats,
        'seatsLeft': seats,
        'price': price,
        'status': 'open',
      });
  await ride('future', day(1));
  await ride('past', day(-2));
  return db;
}

/// Réservation acceptée de [passenger] sur le trajet [rideId] (place déjà décomptée).
Future<String> acceptedBooking(FakeFirebaseFirestore db, String rideId, String passenger) async {
  final ref = await db.collection('bookings').add({
    'rideId': rideId,
    'passengerId': passenger,
    'driverId': 'amira',
    'status': 'accepted',
    'createdAt': Timestamp.now(),
  });
  await db.doc('rides/$rideId').update({'seatsLeft': FieldValue.increment(-1)});
  return ref.id;
}

Future<List<Map<String, dynamic>>> notificationsOf(FakeFirebaseFirestore db, String uid) async =>
    (await db.collection('notifications').where('userId', isEqualTo: uid).get()).docs.map((d) => d.data()).toList();
