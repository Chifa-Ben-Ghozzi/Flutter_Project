import 'package:cloud_firestore/cloud_firestore.dart';

/// Conversion des documents Firestore vers le JSON attendu par les modèles (fromJson).
class Mappers {
  /// Timestamp Firestore -> texte ISO 8601.
  static String iso(dynamic v) => v is Timestamp ? v.toDate().toUtc().toIso8601String() : (v as String? ?? '');

  /// Profil public (avec l'email seulement pour l'utilisateur connecté) et note moyenne calculée.
  static Map<String, dynamic> user(DocumentSnapshot<Map<String, dynamic>> d, {bool full = false}) {
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

  static Map<String, dynamic> ride(DocumentSnapshot<Map<String, dynamic>> d) => {...?d.data(), 'id': d.id};

  static Map<String, dynamic> booking(DocumentSnapshot<Map<String, dynamic>> d) {
    final b = d.data()!;
    return {...b, 'id': d.id, 'createdAt': iso(b['createdAt'])};
  }

  /// Date et heure de départ d'un trajet (champs "date" et "time").
  static DateTime rideDate(Map<String, dynamic> r) => DateTime.parse('${r['date']}T${r['time']}:00');
}
