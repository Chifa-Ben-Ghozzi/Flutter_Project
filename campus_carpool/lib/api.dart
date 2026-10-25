import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Erreur métier (message en français, traduit par L10n.trServer).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Firebase injoignable (pas de réseau).
class NetworkException implements Exception {}

/// En ligne / hors ligne : affiché par la bannière de l'écran d'accueil.
class NetworkStatus extends ChangeNotifier {
  bool _online = true;
  bool get online => _online;
  void set(bool v) {
    if (v == _online) return;
    _online = v;
    notifyListeners();
  }
}

/// Accès aux données de l'application dans Cloud Firestore (Firebase).
///
/// Collections :
///   users/{uid}            profil, note (ratingSum / ratingCount), jetons de notification
///   rides/{id}             trajets
///   bookings/{id}          demandes de place
///   reviews/{ride_from_to} avis (un seul par personne et par trajet)
///   notifications/{id}     notifications de chaque utilisateur
///
/// Les règles de sécurité (firestore.rules) empêchent toute écriture interdite
/// côté serveur ; les vérifications ici donnent des messages clairs à l'utilisateur.
class Api {
  /// Remplaçable dans les tests par FakeFirebaseFirestore.
  static FirebaseFirestore? _db;
  static FirebaseFirestore get db => _db ??= FirebaseFirestore.instance;
  static set db(FirebaseFirestore v) => _db = v;

  /// Client HTTP pour les services externes (géocodage, itinéraire) ; remplaçable dans les tests.
  static http.Client client = http.Client();

  /// Utilisateur connecté (uid Firebase Auth), renseigné par AuthProvider.
  static String? uid;

  static final network = NetworkStatus();

  static CollectionReference<Map<String, dynamic>> get _users => db.collection('users');
  static CollectionReference<Map<String, dynamic>> get _rides => db.collection('rides');
  static CollectionReference<Map<String, dynamic>> get _bookings => db.collection('bookings');
  static CollectionReference<Map<String, dynamic>> get _reviews => db.collection('reviews');
  static CollectionReference<Map<String, dynamic>> get _notifs => db.collection('notifications');

  static String get _me {
    final u = uid;
    if (u == null) throw ApiException('Non authentifié');
    return u;
  }

  /// Exécute une opération Firestore en traduisant les erreurs techniques.
  static Future<T> _run<T>(Future<T> Function() f) async {
    try {
      final r = await f();
      network.set(true);
      return r;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        network.set(false);
        throw NetworkException();
      }
      if (e.code == 'permission-denied') throw ApiException('Action non autorisée');
      if (e.code == 'not-found') throw ApiException('Introuvable');
      rethrow;
    }
  }

  // ---------- Conversion document -> JSON attendu par les modèles ----------

  static String _iso(dynamic v) => v is Timestamp ? v.toDate().toUtc().toIso8601String() : (v as String? ?? '');

  static Map<String, dynamic> _userJson(DocumentSnapshot<Map<String, dynamic>> d, {bool full = false}) {
    final u = d.data() ?? {};
    final count = (u['ratingCount'] as num?)?.toInt() ?? 0;
    final sum = (u['ratingSum'] as num?)?.toDouble() ?? 0;
    return {
      'id': d.id,
      'name': u['name'] ?? '',
      if (full) 'email': u['email'],
      'phone': u['phone'] ?? '',
      'car': {'model': u['carModel'] ?? '', 'plate': u['carPlate'] ?? ''},
      'photo': u['photo'],
      'rating': count == 0 ? null : (sum / count * 10).round() / 10,
      'ratingCount': count,
    };
  }

  static Map<String, dynamic> _rideJson(DocumentSnapshot<Map<String, dynamic>> d) => {...?d.data(), 'id': d.id};

  static Map<String, dynamic> _bookingJson(DocumentSnapshot<Map<String, dynamic>> d) {
    final b = d.data()!;
    return {...b, 'id': d.id, 'createdAt': _iso(b['createdAt'])};
  }

  /// Profils publics (sans photo pour les listes), lus en parallèle.
  static Future<Map<String, Map<String, dynamic>>> _usersById(Iterable<String> ids, {bool photo = false}) async {
    final unique = ids.toSet().where((id) => id.isNotEmpty).toList();
    final docs = await Future.wait(unique.map((id) => _users.doc(id).get()));
    return {
      for (final d in docs)
        if (d.exists) d.id: (_userJson(d)..removeWhere((k, _) => k == 'photo' && !photo)),
    };
  }

  static DateTime _rideDate(Map<String, dynamic> r) => DateTime.parse('${r['date']}T${r['time']}:00');

  // ---------- Compte ----------

  static Future<AppUser> me() => _run(() async {
        final d = await _users.doc(_me).get();
        if (!d.exists) throw ApiException('Utilisateur introuvable');
        return AppUser.fromJson(_userJson(d, full: true));
      });

  /// Crée le profil Firestore juste après l'inscription Firebase Auth.
  static Future<AppUser> createProfile(String email, String name) => _run(() async {
        await _users.doc(_me).set({
          'email': email.toLowerCase(),
          'name': name,
          'phone': '',
          'carModel': '',
          'carPlate': '',
          'photo': null,
          'ratingSum': 0,
          'ratingCount': 0,
          'fcmTokens': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        });
        return me();
      });

  static Future<AppUser> updateProfile(Map<String, dynamic> body) => _run(() async {
        final car = body['car'] as Map?;
        await _users.doc(_me).update({
          if (body['name'] != null) 'name': body['name'],
          if (body.containsKey('phone')) 'phone': body['phone'],
          if (car != null) 'carModel': car['model'] ?? '',
          if (car != null) 'carPlate': car['plate'] ?? '',
          if (body.containsKey('photo')) 'photo': body['photo'],
        });
        return me();
      });

  static Future<void> setUserField(String field, Object value) => _run(() => _users.doc(_me).update({field: value}));

  static Future<AppUser> publicUser(String id) => _run(() async {
        final d = await _users.doc(id).get();
        if (!d.exists) throw ApiException('Utilisateur introuvable');
        final reviews = (await _reviews.where('toId', isEqualTo: id).get()).docs.map((r) {
          final v = r.data();
          return {...v, 'id': r.id, 'from': v['fromName'] ?? '', 'createdAt': _iso(v['createdAt'])};
        }).toList()
          ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
        return AppUser.fromJson({..._userJson(d), 'reviews': reviews.take(20).toList()});
      });

  // ---------- Trajets ----------

  /// Recherche : trajets ouverts, à venir, des autres conducteurs, avec filtres.
  static Future<List<Ride>> searchRides(Map<String, String> q) => _run(() async {
        final me = _me;
        final now = DateTime.now();
        final dest = q['destination']?.toLowerCase();
        final maxPrice = double.tryParse(q['maxPrice'] ?? '');
        final minSeats = int.tryParse(q['minSeats'] ?? '');
        final rides = (await _rides.where('status', isEqualTo: 'open').get())
            .docs
            .map(_rideJson)
            .where((r) => r['driverId'] != me && (r['seatsLeft'] as num) > 0 && _rideDate(r).isAfter(now))
            .where((r) => dest == null || (r['to'] as String).toLowerCase().contains(dest))
            .where((r) => q['date'] == null || r['date'] == q['date'])
            .where((r) => maxPrice == null || (r['price'] as num) <= maxPrice)
            .where((r) => minSeats == null || (r['seatsLeft'] as num) >= minSeats)
            .toList()
          ..sort((a, b) => _rideDate(a).compareTo(_rideDate(b)));
        final drivers = await _usersById(rides.map((r) => r['driverId'] as String));
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
  static Future<void> postRide(Map<String, dynamic> b) => _run(() async {
        final date = DateTime.parse('${b['date']}T${b['time']}:00');
        if (date.isBefore(DateTime.now())) throw ApiException('Date/heure invalide');
        final seats = b['seats'] as int;
        final coords = await geocodeRoute(b['from'], b['to']);
        await _rides.add({
          'driverId': _me,
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
  static Future<List<Ride>> myRides() => _run(() async {
        final me = _me;
        final rides = (await _rides.where('driverId', isEqualTo: me).get()).docs.map(_rideJson).toList()
          ..sort((a, b) => _rideDate(b).compareTo(_rideDate(a)));
        final bookings = (await _bookings.where('driverId', isEqualTo: me).get()).docs.map(_bookingJson).toList();
        final people = await _usersById([me, ...bookings.map((b) => b['passengerId'] as String)]);
        return rides.map((r) {
          final mine = bookings.where((b) => b['rideId'] == r['id']).map((b) => {...b, 'passenger': people[b['passengerId']]});
          return Ride.fromJson({...r, 'driver': people[me], 'bookings': mine.toList()});
        }).toList();
      });

  /// Détails d'un trajet + ce que l'utilisateur connecté peut faire (réserver, appeler, noter).
  static Future<RideDetails> rideDetails(String id) => _run(() async {
        final me = _me;
        final rd = await _rides.doc(id).get();
        if (!rd.exists) throw ApiException('Trajet introuvable');
        final r = _rideJson(rd);
        final isDriver = r['driverId'] == me;
        final all = (await _bookings.where('rideId', isEqualTo: id).get()).docs.map(_bookingJson).toList()
          ..sort((a, b) => (a['createdAt'] as String).compareTo(b['createdAt'] as String));
        final mineAll = all.where((b) => b['passengerId'] == me).toList();
        final myBooking = mineAll.where((b) => b['status'] == 'pending' || b['status'] == 'accepted').firstOrNull ??
            mineAll.lastOrNull;
        final accepted = all.where((b) => b['status'] == 'accepted').toList();
        final finished = r['status'] != 'cancelled' && _rideDate(r).isBefore(DateTime.now());
        // Le conducteur voit toutes les demandes ; les autres ne voient que les passagers acceptés
        final visible = isDriver ? all : accepted;
        final people = await _usersById([r['driverId'], ...visible.map((b) => b['passengerId'] as String)]);
        final driverDoc = await _users.doc(r['driverId']).get();

        var rateable = <String>[];
        if (finished) {
          if (isDriver) {
            rateable = accepted.map((b) => b['passengerId'] as String).toList();
          } else if (myBooking?['status'] == 'accepted') {
            rateable = [r['driverId'] as String];
          }
        }
        if (rateable.isNotEmpty) {
          final done = (await _reviews.where('rideId', isEqualTo: id).where('fromId', isEqualTo: me).get())
              .docs
              .map((d) => d.data()['toId']);
          rateable.removeWhere(done.contains);
        }
        final toRate = rateable.map((u) => people[u] ?? {'id': u, 'name': '?'}).toList();

        return RideDetails.fromJson({
          ...r,
          'driver': driverDoc.exists ? _userJson(driverDoc) : {'id': r['driverId'], 'name': '?'},
          'isDriver': isDriver,
          'finished': finished,
          'myBooking': myBooking,
          'bookings': visible.map((b) => {...b, 'passenger': people[b['passengerId']]}).toList(),
          'toRate': toRate,
        });
      });

  /// Le conducteur annule son trajet : toutes les demandes actives sont annulées et les passagers prévenus.
  static Future<void> cancelRide(String id) => _run(() async {
        final me = _me;
        final rd = await _rides.doc(id).get();
        final r = rd.data();
        if (r == null || r['driverId'] != me) throw ApiException('Trajet introuvable');
        final active = (await _bookings.where('rideId', isEqualTo: id).get())
            .docs
            .where((d) => d.data()['status'] == 'pending' || d.data()['status'] == 'accepted');
        final myName = await _myName();
        final batch = db.batch();
        batch.update(rd.reference, {'status': 'cancelled', 'seatsLeft': r['seats']});
        for (final b in active) {
          batch.update(b.reference, {'status': 'cancelled'});
          _notify(batch, b.data()['passengerId'], 'ride_cancelled', r, id, {'name': myName});
        }
        await batch.commit();
      });

  // ---------- Réservations ----------

  static Future<void> book(String rideId) => _run(() async {
        final me = _me;
        final rd = await _rides.doc(rideId).get();
        final r = rd.data();
        if (r == null || r['status'] != 'open') throw ApiException('Trajet indisponible');
        if (r['driverId'] == me) throw ApiException('Vous ne pouvez pas réserver votre propre trajet');
        if (_rideDate(r).isBefore(DateTime.now())) throw ApiException('Ce trajet est déjà passé');
        if ((r['seatsLeft'] as num) < 1) throw ApiException('Plus de places');
        final mine = await _bookings.where('rideId', isEqualTo: rideId).where('passengerId', isEqualTo: me).get();
        if (mine.docs.any((d) => d.data()['status'] == 'pending' || d.data()['status'] == 'accepted')) {
          throw ApiException('Vous avez déjà une demande pour ce trajet');
        }
        final myName = await _myName();
        final batch = db.batch();
        batch.set(_bookings.doc(), {
          'rideId': rideId,
          'passengerId': me,
          'driverId': r['driverId'],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        _notify(batch, r['driverId'], 'booking_new', r, rideId, {'name': myName});
        await batch.commit();
      });

  /// Mes réservations (passager) avec le trajet et son conducteur.
  static Future<List<Booking>> myBookings() => _run(() async {
        final bookings = (await _bookings.where('passengerId', isEqualTo: _me).get()).docs.map(_bookingJson).toList();
        final rideDocs = await Future.wait(bookings.map((b) => b['rideId'] as String).toSet().map((id) => _rides.doc(id).get()));
        final rides = {for (final d in rideDocs) if (d.exists) d.id: _rideJson(d)};
        final drivers = await _usersById(rides.values.map((r) => r['driverId'] as String));
        final list = bookings
            .where((b) => rides.containsKey(b['rideId']))
            .map((b) {
              final r = rides[b['rideId']]!;
              return Booking.fromJson({...b, 'ride': {...r, 'driver': drivers[r['driverId']]}});
            })
            .toList()
          ..sort((a, b) => b.ride!.dateTime.compareTo(a.ride!.dateTime));
        return list;
      });

  /// Le conducteur accepte (une place en moins) ou refuse une demande.
  static Future<void> respond(String bookingId, bool accept) => _run(() async {
        final me = _me;
        final myName = await _myName();
        await db.runTransaction((tx) async {
          final bRef = _bookings.doc(bookingId);
          final b = (await tx.get(bRef)).data();
          if (b == null || b['driverId'] != me) throw ApiException('Réservation introuvable');
          final rRef = _rides.doc(b['rideId']);
          final r = (await tx.get(rRef)).data()!;
          if (b['status'] != 'pending') throw ApiException('Demande déjà traitée');
          if (accept) {
            if ((r['seatsLeft'] as num) < 1) throw ApiException('Plus de places disponibles');
            tx.update(rRef, {'seatsLeft': FieldValue.increment(-1)});
            tx.update(bRef, {'status': 'accepted'});
          } else {
            tx.update(bRef, {'status': 'declined'});
          }
          _notify(tx, b['passengerId'], accept ? 'booking_accepted' : 'booking_declined', r, b['rideId'], {'name': myName});
        });
      });

  /// Le passager annule sa demande ; si elle était acceptée, la place est rendue au trajet.
  static Future<void> cancelBooking(String bookingId) => _run(() async {
        final me = _me;
        final myName = await _myName();
        await db.runTransaction((tx) async {
          final bRef = _bookings.doc(bookingId);
          final b = (await tx.get(bRef)).data();
          if (b == null || b['passengerId'] != me || !(b['status'] == 'pending' || b['status'] == 'accepted')) {
            throw ApiException('Réservation introuvable');
          }
          final rRef = _rides.doc(b['rideId']);
          final r = (await tx.get(rRef)).data()!;
          if (b['status'] == 'accepted') {
            // lastBooking permet aux règles de vérifier que c'est bien une place rendue par ce passager
            tx.update(rRef, {'seatsLeft': FieldValue.increment(1), 'lastBooking': bookingId});
          }
          tx.update(bRef, {'status': 'cancelled'});
          _notify(tx, b['driverId'], 'booking_cancelled', r, b['rideId'], {'name': myName});
        });
      });

  // ---------- Avis ----------

  /// Note une personne après un trajet partagé (un seul avis par personne et par trajet).
  static Future<void> review(String rideId, String toId, int stars, String comment) => _run(() async {
        final me = _me;
        if (stars < 1 || stars > 5) throw ApiException('Note entre 1 et 5');
        final r = (await _rides.doc(rideId).get()).data();
        if (r == null) throw ApiException('Trajet introuvable');
        if (r['status'] == 'cancelled' || _rideDate(r).isAfter(DateTime.now())) {
          throw ApiException('Vous pourrez noter après le trajet');
        }
        // La réservation acceptée qui relie les deux personnes (vérifiée aussi par les règles)
        final passenger = r['driverId'] == me ? toId : me;
        final link = (await _bookings.where('rideId', isEqualTo: rideId).where('passengerId', isEqualTo: passenger).get())
            .docs
            .where((d) => d.data()['status'] == 'accepted')
            .firstOrNull;
        final allowed = link != null && (r['driverId'] == me || r['driverId'] == toId) && toId != me;
        if (!allowed) throw ApiException('Vous ne pouvez pas noter cette personne pour ce trajet');
        final reviewId = '${rideId}_${me}_$toId';
        if ((await _reviews.doc(reviewId).get()).exists) throw ApiException('Avis déjà envoyé');
        final myName = await _myName();
        final batch = db.batch();
        batch.set(_reviews.doc(reviewId), {
          'rideId': rideId,
          'bookingId': link.id,
          'fromId': me,
          'fromName': myName,
          'toId': toId,
          'stars': stars,
          'comment': comment.length > 300 ? comment.substring(0, 300) : comment,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.update(_users.doc(toId), {
          'ratingSum': FieldValue.increment(stars),
          'ratingCount': FieldValue.increment(1),
          'lastReview': reviewId,
        });
        _notify(batch, toId, 'review', r, rideId, {'name': myName, 'stars': stars});
        await batch.commit();
      });

  // ---------- Notifications ----------

  static Query<Map<String, dynamic>> myNotificationsQuery() => _notifs.where('userId', isEqualTo: _me);

  static AppNotification notificationFrom(DocumentSnapshot<Map<String, dynamic>> d) {
    final n = d.data()!;
    return AppNotification.fromJson({
      ...n,
      'id': d.id,
      // Juste après la création, l'heure du serveur n'est pas encore connue
      'createdAt': n['createdAt'] == null ? DateTime.now().toUtc().toIso8601String() : _iso(n['createdAt']),
    });
  }

  static Future<List<AppNotification>> notifications() => _run(() async {
        final list = (await myNotificationsQuery().get()).docs.map(notificationFrom).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(50).toList();
      });

  static Future<void> markNotificationsRead() => _run(() async {
        final unread = (await myNotificationsQuery().where('read', isEqualTo: false).get()).docs;
        if (unread.isEmpty) return;
        final batch = db.batch();
        for (final d in unread) {
          batch.update(d.reference, {'read': true});
        }
        await batch.commit();
      });

  /// Ajoute une notification pour [userId] (dans un batch ou une transaction).
  /// `data` permet à l'app et au serveur de notifications d'écrire le texte dans la langue de chacun.
  static void _notify(dynamic writer, String userId, String type, Map<String, dynamic> ride, String rideId,
      Map<String, dynamic> extra) {
    final doc = {
      'userId': userId,
      'type': type,
      'rideId': rideId,
      'data': {'from': ride['from'], 'to': ride['to'], 'date': ride['date'], 'time': ride['time'], ...extra},
      'read': false,
      'pushed': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final ref = _notifs.doc();
    if (writer is WriteBatch) {
      writer.set(ref, doc);
    } else {
      (writer as Transaction).set(ref, doc);
    }
  }

  static Future<String> _myName() async => ((await _users.doc(_me).get()).data()?['name'] as String?) ?? '';

  // ---------- Géocodage (OpenStreetMap Nominatim, gratuit) ----------

  /// Coordonnées du départ et de l'arrivée, ou null si le service ne répond pas.
  static Future<Map<String, double>?> geocodeRoute(String from, String to) async {
    final a = await geocode(from);
    final b = await geocode(to);
    if (a == null || b == null) return null;
    return {'fromLat': a.$1, 'fromLng': a.$2, 'toLat': b.$1, 'toLng': b.$2};
  }

  static Future<(double, double)?> geocode(String place) async {
    Future<(double, double)?> search(String extra) async {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&limit=1$extra'
          '&q=${Uri.encodeQueryComponent(place)}');
      final r = await client.get(url, headers: kIsWeb ? null : {'User-Agent': 'CampusCarpool/1.0 (student project)'})
          .timeout(const Duration(seconds: 6));
      final list = jsonDecode(r.body) as List;
      if (list.isEmpty) return null;
      return (double.parse(list.first['lat']), double.parse(list.first['lon']));
    }

    try {
      return await search('&countrycodes=tn') ?? await search('');
    } catch (_) {
      return null; // pas de carte pour ce trajet
    }
  }
}
