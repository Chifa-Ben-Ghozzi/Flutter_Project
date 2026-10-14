import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';

class PostRideScreen extends StatefulWidget {
  const PostRideScreen({super.key});
  @override
  State<PostRideScreen> createState() => _PostRideScreenState();
}

class _PostRideScreenState extends State<PostRideScreen> {
  final from = TextEditingController();
  final to = TextEditingController();
  final seats = TextEditingController(text: '3');
  final price = TextEditingController();
  DateTime? date;
  TimeOfDay? time;
  bool busy = false;

  Future<void> submit() async {
    if (from.text.trim().isEmpty || to.text.trim().isEmpty || date == null || time == null ||
        seats.text.isEmpty || price.text.isEmpty) {
      toast(context, 'Remplissez tous les champs');
      return;
    }
    setState(() => busy = true);
    final ok = await guard(context, () => Api.postRide({
          'from': from.text.trim(),
          'to': to.text.trim(),
          'date': fmtDate(date!),
          'time': '${two(time!.hour)}:${two(time!.minute)}',
          'seats': int.tryParse(seats.text) ?? 0,
          'price': double.tryParse(price.text.replaceAll(',', '.')) ?? -1,
        }));
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      toast(context, 'Trajet publié ✅');
      from.clear(); to.clear(); price.clear();
      setState(() { date = null; time = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Publier un trajet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      TextField(controller: from, decoration: const InputDecoration(labelText: 'Départ', prefixIcon: Icon(Icons.trip_origin), border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: to, decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.place), border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => date = d);
          },
          icon: const Icon(Icons.calendar_today),
          label: Text(date == null ? 'Date' : fmtDate(date!)),
        )),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
            if (t != null) setState(() => time = t);
          },
          icon: const Icon(Icons.access_time),
          label: Text(time == null ? 'Heure' : '${two(time!.hour)}:${two(time!.minute)}'),
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Places', prefixIcon: Icon(Icons.event_seat), border: OutlineInputBorder()))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Prix (€)', prefixIcon: Icon(Icons.euro), border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 20),
      FilledButton(onPressed: busy ? null : submit, child: const Text('Publier')),
    ]);
  }
}
