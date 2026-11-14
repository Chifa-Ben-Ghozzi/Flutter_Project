import 'app_user.dart';
import 'ride.dart';

/// Un message de la messagerie entre un conducteur et un passager (une conversation par réservation).
class ChatMessage {
  final String id;
  final String bookingId;
  final String rideId;
  final String from; // uid de l'auteur
  final String to; // uid du destinataire
  final String fromName;
  final String toName;
  final String route; // "Ariana → Esprit Ghazela", pour la liste des conversations
  final String text;
  final DateTime createdAt;
  final bool read; // lu par le destinataire

  const ChatMessage({
    required this.id,
    required this.bookingId,
    required this.rideId,
    required this.from,
    required this.to,
    this.fromName = '',
    this.toName = '',
    this.route = '',
    required this.text,
    required this.createdAt,
    this.read = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'],
        bookingId: j['bookingId'] ?? '',
        rideId: j['rideId'] ?? '',
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        fromName: j['fromName'] ?? '',
        toName: j['toName'] ?? '',
        route: j['route'] ?? '',
        text: j['text'] ?? '',
        // Juste après l'envoi, l'heure du serveur n'est pas encore connue
        createdAt: DateTime.tryParse(j['createdAt'] ?? '')?.toLocal() ?? DateTime.now(),
        read: j['read'] ?? false,
      );
}

/// Une conversation de la boîte de réception : dernier message et nombre de messages non lus.
class Conversation {
  final String bookingId;
  final String rideId;
  final String otherId;
  final String otherName;
  final String route;
  final ChatMessage last;
  final int unread;

  const Conversation({
    required this.bookingId,
    required this.rideId,
    required this.otherId,
    required this.otherName,
    required this.route,
    required this.last,
    required this.unread,
  });
}

/// En-tête d'une conversation : l'autre personne, le trajet, et si on peut encore écrire.
class ChatInfo {
  final String bookingId;
  final AppUser other;
  final Ride ride;
  final bool iAmDriver;

  /// On peut écrire tant que la demande est en attente ou acceptée.
  final bool open;

  const ChatInfo({
    required this.bookingId,
    required this.other,
    required this.ride,
    required this.iAmDriver,
    required this.open,
  });
}
