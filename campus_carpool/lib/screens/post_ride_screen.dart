import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../validators.dart';
import '../widgets.dart';

class PostRideScreen extends StatefulWidget {
  const PostRideScreen({super.key});
  @override
  State<PostRideScreen> createState() => _PostRideScreenState();
}

class _PostRideScreenState extends State<PostRideScreen> {
  // Clé du formulaire : permet d'appeler validate() / reset() sur tous les champs
  final formKey = GlobalKey<FormState>();
  final from = TextEditingController();
  final to = TextEditingController();
  final dateCtrl = TextEditingController();
  final timeCtrl = TextEditingController();
  final seats = TextEditingController(text: '3');
  final price = TextEditingController();
  DateTime? date;
  TimeOfDay? time;
  bool busy = false;

  @override
  void dispose() {
    for (final c in [from, to, dateCtrl, timeCtrl, seats, price]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Traduit la clé renvoyée par un validator (null = valide).
  String? t(String? key) => key == null ? null : context.tr(key);

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => dateCtrl.text = fmtDate(date = d));
  }

  Future<void> pickTime() async {
    final tm = await showTimePicker(context: context, initialTime: time ?? TimeOfDay.now());
    if (tm != null) setState(() => timeCtrl.text = '${two((time = tm).hour)}:${two(tm.minute)}');
  }

  Future<void> submit() async {
    // Lance tous les validators : affiche les erreurs sous les champs et bloque si invalide
    if (!formKey.currentState!.validate()) return;
    final done = context.tr('toast_ride_posted');
    setState(() => busy = true);
    final ok = await guard(context, () => Api.postRide({
          'from': from.text.trim(),
          'to': to.text.trim(),
          'date': fmtDate(date!),
          'time': timeCtrl.text,
          'seats': int.parse(seats.text.trim()),
          'price': Validators.parsePrice(price.text),
        }));
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      toast(context, done);
      formKey.currentState!.reset();
      for (final c in [from, to, dateCtrl, timeCtrl, price]) {
        c.clear();
      }
      seats.text = '3';
      setState(() {
        date = null;
        time = null;
      });
    }
  }

  InputDecoration deco(String key, IconData icon) =>
      InputDecoration(labelText: context.tr(key), prefixIcon: Icon(icon), border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      // Les erreurs se mettent à jour pendant la saisie
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(context.tr('post_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(context.tr('post_subtitle'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextFormField(
          controller: from,
          textInputAction: TextInputAction.next,
          decoration: deco('departure', Icons.trip_origin),
          validator: (v) => t(Validators.place(v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: to,
          textInputAction: TextInputAction.next,
          decoration: deco('destination', Icons.place),
          validator: (v) => t(Validators.destination(v, from.text)),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextFormField(
              controller: dateCtrl,
              readOnly: true,
              onTap: pickDate,
              decoration: deco('date', Icons.calendar_today),
              validator: (_) => date == null ? context.tr('v_pick_date') : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: timeCtrl,
              readOnly: true,
              onTap: pickTime,
              decoration: deco('time', Icons.access_time),
              validator: (_) => date == null ? null : t(Validators.dateTime(date, time?.hour, time?.minute)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextFormField(
              controller: seats,
              keyboardType: TextInputType.number,
              decoration: deco('seats', Icons.event_seat),
              validator: (v) => t(Validators.seats(v)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: deco('price_dt', Icons.payments_outlined),
              validator: (v) => t(Validators.price(v)),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : submit,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.publish),
          label: Text(context.tr('publish')),
        ),
      ]),
    );
  }
}
