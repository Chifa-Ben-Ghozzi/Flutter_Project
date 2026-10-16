import 'package:flutter/material.dart';
import 'api.dart';

DateTime rideDt(Map r) => DateTime.parse('${r['date']}T${r['time']}:00');
bool isPast(Map r) => rideDt(r).isBefore(DateTime.now());
String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Exécute un appel API en affichant l'erreur éventuelle. Retourne true si succès.
Future<bool> guard(BuildContext c, Future<void> Function() f) async {
  try {
    await f();
    return true;
  } on ApiException catch (e) {
    if (c.mounted) toast(c, e.message);
  } catch (_) {
    if (c.mounted) toast(c, 'Serveur injoignable');
  }
  return false;
}

Widget statusChip(String s) {
  const labels = {
    'pending': 'En attente', 'accepted': 'Acceptée', 'declined': 'Refusée',
    'cancelled': 'Annulée', 'open': 'Ouvert',
  };
  const colors = {
    'pending': Colors.orange, 'accepted': Colors.green, 'declined': Colors.red,
    'cancelled': Colors.grey, 'open': Colors.blue,
  };
  return Chip(
    label: Text(labels[s] ?? s, style: const TextStyle(color: Colors.white, fontSize: 12)),
    backgroundColor: colors[s] ?? Colors.grey,
    visualDensity: VisualDensity.compact,
  );
}

class RideInfo extends StatelessWidget {
  final Map ride;
  const RideInfo(this.ride, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = ride['driver'] ?? {};
    final car = d['car'] ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${ride['from']} → ${ride['to']}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('📅 ${ride['date']}  🕒 ${ride['time']}'),
      Text('💶 ${ride['price']} dt   💺 ${ride['seatsLeft']}/${ride['seats']} places'),
      Text('👤 ${d['name'] ?? ''}${(d['phone'] ?? '').toString().isNotEmpty ? ' · ${d['phone']}' : ''}'),
      if ((car['model'] ?? '').toString().isNotEmpty) Text('🚗 ${car['model']} ${car['plate'] ?? ''}'),
    ]);
  }
}
