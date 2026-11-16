/// Valeurs proposées par l'assistant pour pré-remplir le formulaire « Publier un trajet ».
/// L'utilisateur vérifie le formulaire et publie lui-même.
class RidePrefill {
  final String from;
  final String to;
  final DateTime? date; // jour seulement
  final int? hour, minute;
  final int? seats;
  final double? price;

  const RidePrefill({required this.from, required this.to, this.date, this.hour, this.minute, this.seats, this.price});

  String get route => '$from → $to';

  /// Les valeurs viennent d'un modèle d'IA : tout ce qui est mal formé ou hors limites est ignoré.
  factory RidePrefill.fromJson(Map<String, dynamic> j) {
    final day = j['date'] is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(j['date']) ? DateTime.tryParse(j['date']) : null;
    final time = j['time'] is String ? RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(j['time']) : null;
    final h = time == null ? null : int.parse(time[1]!);
    final m = time == null ? null : int.parse(time[2]!);
    final validTime = h != null && m != null && h < 24 && m < 60;
    final seats = j['seats'] is num ? (j['seats'] as num).toInt() : null;
    final price = j['price'] is num ? (j['price'] as num).toDouble() : null;
    return RidePrefill(
      from: j['from'] is String ? (j['from'] as String).trim() : '',
      to: j['to'] is String ? (j['to'] as String).trim() : '',
      date: day,
      hour: validTime ? h : null,
      minute: validTime ? m : null,
      seats: seats != null && seats >= 1 && seats <= 8 ? seats : null,
      price: price != null && price >= 0 ? price : null,
    );
  }
}
