/// Une notification (nouvelle demande, acceptation, annulation, avis…).
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
