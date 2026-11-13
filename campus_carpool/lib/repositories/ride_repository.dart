import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/exceptions.dart';
import '../services/firestore_service.dart';
import '../services/geocoding_service.dart';
import 'mappers.dart';
import 'notification_repository.dart';
import 'review_repository.dart';
import 'user_repository.dart';

/// Trajets : recherche, publication, mes trajets, détails, annulation, fin du trajet.
class RideRepository {
  static CollectionReference<Map<String, dynamic>> get _rides => FirestoreService.rides;
  static CollectionReference<Map<String, dynamic>> get _bookings => FirestoreService.bookings;

  /// Recherche : trajets ouverts, à venir, des autres conducteurs, avec filtres
  /// (from, destination, date, maxPrice, minSeats).
  static Future<List<Ride>> search(Map<String, String> q) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final now = DateTime.now();
        final from = q['from']?.toLowerCase();
        final dest = q['destination']?.toLowerCase();
        final maxPrice = double.tryParse(q['maxPrice'] ?? '');
        final minSeats = int.tryParse(q['minSeats'] ?? '');
        final rides = (await _rides.where('status', isEqualTo: 'open').get())
            .docs
            .map(Mappers.ride)
            .where((r) => r['driverId'] != me && (r['seatsLeft'] as num) > 0 && Mappers.rideDate(r).isAfter(now))
            .where((r) => from == null || (r['from'] as String).toLowerCase().contains(from))
            .where((r) => dest == null || (r['to'] as String).toLowerCase().contains(dest))
            .where((r) => q['date'] == null || r['date'] == q['date'])
            .where((r) => maxPrice == null || (r['price'] as num) <= maxPrice)
            .where((r) => minSeats == null || (r['seatsLeft'] as num) >= minSeats)
            .toList()
          ..sort((a, b) => Mappers.rideDate(a).compareTo(Mappers.rideDate(b)));
        final drivers = await UserRepository.byIds(rides.map((r) => r['driverId'] as String));
        final mine = (await _bookings.where('passengerId', isEqualTo: me).get()).docs.map((d) => d.data());
        final myStatus = {
          for (final b in mine)
            if (b['status'] == 'pending' || b['status'] == 'accepted') b['rideId']: b['status'],
        };
        return rides
            .map((r) => Ride.fromJson({...r, 'driver': drivers[r['driverId']], 'myBooking': myStatus[r['id']]}))
            .toList();
      });

  /// Publie un trajet (avec ses coordonnées pour la carte quand le géocodage répond).
  static Future<void> publish(Map<String, dynamic> b) => FirestoreService.run(() async {
        final date = DateTime.parse('${b['date']}T${b['time']}:00');
        if (date.isBefore(DateTime.now())) throw ApiException('Date/heure invalide');
        final seats = b['seats'] as int;
        final coords = await GeocodingService.geocodeRoute(b['from'], b['to']);
        await _rides.add({
          'driverId': FirestoreService.currentUid,
          'from': b['from'],
          'to': b['to'],
          'date': b['date'],
          'time': b['time'],
          'dateTime': Timestamp.fromDate(date),
          'seats': seats,
          'seatsLeft': seats,
          'price': b['price'],
          'status': 'open',
          'createdAt': FieldValue.serverTimestamp(),
          ...?coords,
        });
      });

  /// Mes trajets (conducteur) avec les demandes reçues.
  static Future<List<Ride>> myRides() => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final rides = (await _rides.where('driverId', isEqualTo: me).get()).docs.map(Mappers.ride).toList()
          ..sort((a, b) => Mappers.rideDate(b).compareTo(Mappers.rideDate(a)));
        final bookings = (await _bookings.where('driverId', isEqualTo: me).get()).docs.map(Mappers.booking).toList();
        final people = await UserRepository.byIds([me, ...bookings.map((b) => b['passengerId'] as String)]);
        return rides.map((r) {
          final mine =
              bookings.where((b) => b['rideId'] == r['id']).map((b) => {...b, 'passenger': people[b['passengerId']]});
          return Ride.fromJson({...r, 'driver': people[me], 'bookings': mine.toList()});
        }).toList();
      });

  /// Détails d'un trajet + ce que l'utilisateur connecté peut faire (réserver, appeler, noter).
  static Future<RideDetails> details(String id) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final rd = await _rides.doc(id).get();
        if (!rd.exists) throw ApiException('Trajet introuvable');
        final r = Mappers.ride(rd);
        final isDriver = r['driverId'] == me;
        final all = (await _bookings.where('rideId', isEqualTo: id).get()).docs.map(Mappers.booking).toList()
          ..sort((a, b) => (a['createdAt'] as String).compareTo(b['createdAt'] as String));
        final mineAll = all.where((b) => b['passengerId'] == me).toList();
        final myBooking = mineAll.where((b) => b['status'] == 'pending' || b['status'] == 'accepted').firstOrNull ??
            mineAll.lastOrNull;
        final accepted = all.where((b) => b['status'] == 'accepted').toList();
        final finished =
            r['status'] == 'completed' || (r['status'] != 'cancelled' && Mappers.rideDate(r).isBefore(DateTime.now()));
        // Le conducteur voit toutes les demandes ; les autres ne voient que les passagers acceptés
        final visible = isDriver ? all : accepted;
        final people = await UserRepository.byIds([r['driverId'], ...visible.map((b) => b['passengerId'] as String)]);
        final driver = await UserRepository.byId(r['driverId']);

        var rateable = <String>[];
        if (finished) {
          if (isDriver) {
            rateable = accepted.map((b) => b['passengerId'] as String).toList();
          } else if (myBooking?['status'] == 'accepted') {
            rateable = [r['driverId'] as String];
          }
        }
        if (rateable.isNotEmpty) {
          final done = await ReviewRepository.alreadyRatedBy(id, me);
          rateable.removeWhere(done.contains);
        }
        final toRate = rateable.map((u) => people[u] ?? {'id': u, 'name': '?'}).toList();

        return RideDetails.fromJson({
          ...r,
          'driver': driver ?? {'id': r['driverId'], 'name': '?'},
          'isDriver': isDriver,
          'finished': finished,
          'myBooking': myBooking,
          'bookings': visible.map((b) => {...b, 'passenger': people[b['passengerId']]}).toList(),
          'toRate': toRate,
        });
      });

  /// Le conducteur annule son trajet : toutes les demandes actives sont annulées et les passagers prévenus.
  static Future<void> cancel(String id) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final rd = await _rides.doc(id).get();
        final r = rd.data();
        if (r == null || r['driverId'] != me || r['status'] != 'open') throw ApiException('Trajet introuvable');
        final active = (await _bookings.where('rideId', isEqualTo: id).get())
            .docs
            .where((d) => d.data()['status'] == 'pending' || d.data()['status'] == 'accepted');
        final myName = await UserRepository.myName();
        final batch = FirestoreService.db.batch();
        batch.update(rd.reference, {'status': 'cancelled', 'seatsLeft': r['seats']});
        for (final b in active) {
          batch.update(b.reference, {'status': 'cancelled'});
          NotificationRepository.add(batch, b.data()['passengerId'], 'ride_cancelled', r, id, {'name': myName});
        }
        await batch.commit();
      });

  /// Un passager accepté termine le trajet ; les participants peuvent ensuite se noter.
  static Future<void> end(String rideId, String bookingId) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final myName = await UserRepository.myName();
        final pendingBookings = (await _bookings.where('rideId', isEqualTo: rideId).get())
            .docs
            .where((d) => d.data()['status'] == 'pending')
            .toList();
        await FirestoreService.db.runTransaction((tx) async {
          final rideRef = _rides.doc(rideId);
          final bookingRef = _bookings.doc(bookingId);
          final ride = (await tx.get(rideRef)).data();
          final booking = (await tx.get(bookingRef)).data();
          final pending = <MapEntry<DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>>[];
          for (final doc in pendingBookings) {
            final current = (await tx.get(doc.reference)).data();
            if (current != null && current['status'] == 'pending' && current['driverId'] == ride?['driverId']) {
              pending.add(MapEntry(doc.reference, current));
            }
          }
          if (ride == null || ride['status'] != 'open') throw ApiException('Trajet indisponible');
          if (ride['driverId'] == me ||
              booking == null ||
              booking['rideId'] != rideId ||
              booking['passengerId'] != me ||
              booking['driverId'] != ride['driverId'] ||
              booking['status'] != 'accepted') {
            throw ApiException('Réservation introuvable');
          }
          tx.update(rideRef, {'status': 'completed', 'completionBookingId': bookingId});
          for (final entry in pending) {
            tx.update(entry.key, {'status': 'declined'});
            NotificationRepository.add(tx, entry.value['passengerId'], 'ride_ended', ride, rideId, {'name': myName});
          }
        });
      });
}
