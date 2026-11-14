import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/exceptions.dart';
import '../services/firestore_service.dart';
import 'mappers.dart';
import 'user_repository.dart';

/// Messagerie conducteur ↔ passager, en temps réel (une conversation par réservation).
///
/// Document `messages/{id}` : bookingId, rideId, from, to, fromName, toName, route, text, createdAt, read, pushed.
/// Les règles de sécurité ne laissent lire que ses propres messages (envoyés ou reçus) :
/// chaque lecture combine donc deux requêtes, « envoyés par moi » et « reçus par moi ».
/// Le serveur push envoie une notification au destinataire (champ `pushed`).
class ChatRepository {
  static CollectionReference<Map<String, dynamic>> get _messages => FirestoreService.messages;

  /// Longueur maximale d'un message (même limite que les règles Firestore).
  static const maxLength = 1000;

  static ChatMessage fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return ChatMessage.fromJson({...m, 'id': d.id, 'createdAt': Mappers.iso(m['createdAt'])});
  }

  static Query<Map<String, dynamic>> _sent() => _messages.where('from', isEqualTo: FirestoreService.currentUid);
  static Query<Map<String, dynamic>> _received() => _messages.where('to', isEqualTo: FirestoreService.currentUid);

  /// Messages non lus reçus par l'utilisateur connecté (badge de la messagerie).
  static Query<Map<String, dynamic>> unreadQuery() => _received().where('read', isEqualTo: false);

  /// Les messages d'une conversation, du plus ancien au plus récent, mis à jour en direct.
  static Stream<List<ChatMessage>> watch(String bookingId) => _merge(
        _sent().where('bookingId', isEqualTo: bookingId),
        _received().where('bookingId', isEqualTo: bookingId),
      );

  /// Boîte de réception : une ligne par conversation, la plus récente en premier.
  static Stream<List<Conversation>> conversations() {
    final me = FirestoreService.currentUid;
    return _merge(_sent(), _received()).map((all) => group(all, me));
  }

  /// Regroupe des messages par réservation (fonction pure, testée séparément).
  static List<Conversation> group(List<ChatMessage> all, String me) {
    final byBooking = <String, List<ChatMessage>>{};
    for (final m in all) {
      byBooking.putIfAbsent(m.bookingId, () => []).add(m);
    }
    final list = byBooking.entries.map((e) {
      final msgs = e.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final last = msgs.last;
      final mine = last.from == me;
      return Conversation(
        bookingId: e.key,
        rideId: last.rideId,
        otherId: mine ? last.to : last.from,
        otherName: mine ? last.toName : last.fromName,
        route: last.route,
        last: last,
        unread: msgs.where((m) => m.to == me && !m.read).length,
      );
    }).toList()
      ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
    return list;
  }

  /// Fusionne les résultats de deux requêtes en direct en une seule liste triée par date.
  static Stream<List<ChatMessage>> _merge(Query<Map<String, dynamic>> a, Query<Map<String, dynamic>> b) {
    List<ChatMessage>? listA, listB;
    StreamSubscription? subA, subB;
    late final StreamController<List<ChatMessage>> out;
    void emit() {
      if (listA == null || listB == null) return;
      out.add([...listA!, ...listB!]..sort((x, y) => x.createdAt.compareTo(y.createdAt)));
    }

    out = StreamController<List<ChatMessage>>(
      onListen: () {
        subA = a.snapshots().listen((s) {
          listA = s.docs.map(fromDoc).toList();
          emit();
        }, onError: out.addError);
        subB = b.snapshots().listen((s) {
          listB = s.docs.map(fromDoc).toList();
          emit();
        }, onError: out.addError);
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return out.stream;
  }

  /// En-tête de la conversation : l'autre personne, le trajet, et si on peut encore écrire.
  static Future<ChatInfo> info(String bookingId) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final b = (await FirestoreService.bookings.doc(bookingId).get()).data();
        if (b == null || (b['passengerId'] != me && b['driverId'] != me)) {
          throw ApiException('Réservation introuvable');
        }
        final rd = await FirestoreService.rides.doc(b['rideId']).get();
        if (!rd.exists) throw ApiException('Trajet introuvable');
        final iAmDriver = b['driverId'] == me;
        final otherId = (iAmDriver ? b['passengerId'] : b['driverId']) as String;
        final other = await UserRepository.byId(otherId);
        return ChatInfo(
          bookingId: bookingId,
          other: AppUser.fromJson(other ?? {'id': otherId, 'name': '?'}),
          ride: Ride.fromJson(Mappers.ride(rd)),
          iAmDriver: iAmDriver,
          open: b['status'] == 'pending' || b['status'] == 'accepted',
        );
      });

  /// Envoie un message à l'autre personne de la réservation.
  static Future<void> send(String bookingId, String text) => FirestoreService.run(() async {
        final me = FirestoreService.currentUid;
        final body = text.trim();
        if (body.isEmpty) throw ApiException('Message vide');
        if (body.length > maxLength) throw ApiException('Message trop long');
        final b = (await FirestoreService.bookings.doc(bookingId).get()).data();
        if (b == null || (b['passengerId'] != me && b['driverId'] != me)) {
          throw ApiException('Réservation introuvable');
        }
        if (b['status'] != 'pending' && b['status'] != 'accepted') throw ApiException('Conversation fermée');
        final other = (b['driverId'] == me ? b['passengerId'] : b['driverId']) as String;
        final r = (await FirestoreService.rides.doc(b['rideId']).get()).data() ?? const {};
        final names = await UserRepository.byIds([me, other]);
        await _messages.add({
          'bookingId': bookingId,
          'rideId': b['rideId'],
          'from': me,
          'to': other,
          'fromName': names[me]?['name'] ?? '',
          'toName': names[other]?['name'] ?? '',
          'route': '${r['from'] ?? ''} → ${r['to'] ?? ''}',
          'text': body,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
          'pushed': false,
        });
      });

  /// Marque comme lus les messages reçus dans cette conversation.
  static Future<void> markRead(String bookingId) => FirestoreService.run(() async {
        final unread = (await unreadQuery().where('bookingId', isEqualTo: bookingId).get()).docs;
        if (unread.isEmpty) return;
        final batch = FirestoreService.db.batch();
        for (final d in unread) {
          batch.update(d.reference, {'read': true});
        }
        await batch.commit();
      });
}
