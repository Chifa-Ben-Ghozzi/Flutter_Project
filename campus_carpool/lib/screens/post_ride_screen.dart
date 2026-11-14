import 'package:flutter/material.dart';
import '../l10n.dart';
import '../validators.dart';
import '../widgets.dart';
import '../repositories/ride_repository.dart';

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

  // Trajet régulier : jours de la semaine (1 = lundi … 7 = dimanche) et nombre de semaines
  bool repeat = false;
  final days = <int>{};
  int weeks = 4;
  static const weekOptions = [1, 2, 3, 4, 6, 8];

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
    if (d != null) {
      setState(() {
        dateCtrl.text = fmtDate(date = d);
        if (repeat && days.isEmpty) days.add(d.weekday);
      });
    }
  }

  /// Dates qui seront publiées (trajet régulier), pour le résumé sous le formulaire.
  List<DateTime> get seriesDates {
    if (!repeat || date == null || time == null || days.isEmpty) return const [];
    final first = DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute);
    final now = DateTime.now();
    return RideRepository.occurrences(first, days, weeks).where((d) => d.isAfter(now)).toList();
  }

  Future<void> pickTime() async {
    final tm = await showTimePicker(context: context, initialTime: time ?? TimeOfDay.now());
    if (tm != null) setState(() => timeCtrl.text = '${two((time = tm).hour)}:${two(tm.minute)}');
  }

  Future<void> submit() async {
    // Lance tous les validators : affiche les erreurs sous les champs et bloque si invalide
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    var count = 0;
    final ok = await guard(
        context,
        () async => count = await RideRepository.publish({
              'from': from.text.trim(),
              'to': to.text.trim(),
              'date': fmtDate(date!),
              'time': timeCtrl.text,
              'seats': int.parse(seats.text.trim()),
              'price': Validators.parsePrice(price.text),
              if (repeat) 'repeatDays': days.toList(),
              if (repeat) 'repeatWeeks': weeks,
            }));
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      toast(context, count > 1 ? context.tr('toast_series_posted', {'n': count}) : context.tr('toast_ride_posted'));
      formKey.currentState!.reset();
      for (final c in [from, to, dateCtrl, timeCtrl, price]) {
        c.clear();
      }
      seats.text = '3';
      setState(() {
        date = null;
        time = null;
        repeat = false;
        days.clear();
      });
    }
  }

  InputDecoration deco(String key, IconData icon) =>
      InputDecoration(labelText: context.tr(key), prefixIcon: Icon(icon));

  /// Change le nombre de places avec les boutons − / + (le champ reste modifiable au clavier).
  void stepSeats(int delta) {
    final n = (int.tryParse(seats.text.trim()) ?? 3) + delta;
    seats.text = '${n.clamp(1, 8)}';
    setState(() {});
  }

  void swapPlaces() => setState(() {
        final t = from.text;
        from.text = to.text;
        to.text = t;
      });

  /// Choix des jours (FormField : l'erreur s'affiche comme sous un champ texte) et du nombre de semaines.
  Widget recurrence() {
    final names = context.tr('weekdays').split('|');
    final dates = seriesDates;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FormField<Set<int>>(
        validator: (_) => repeat && days.isEmpty ? context.tr('v_pick_days') : null,
        builder: (field) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(names[d - 1]),
                selected: days.contains(d),
                showCheckmark: false,
                onSelected: (on) {
                  setState(() => on ? days.add(d) : days.remove(d));
                  field.didChange(days);
                },
              ),
          ]),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text(context.tr('repeat_weeks')),
        const Spacer(),
        DropdownButton<int>(
          value: weeks,
          underline: const SizedBox(),
          borderRadius: BorderRadius.circular(12),
          items: [
            for (final w in weekOptions)
              DropdownMenuItem(
                  value: w, child: Text(w == 1 ? context.tr('weeks_one') : context.tr('weeks_other', {'n': w}))),
          ],
          onChanged: (w) => setState(() => weeks = w ?? weeks),
        ),
      ]),
      if (dates.length > 1)
        InfoLine(
          Icons.event_repeat,
          context.tr('repeat_summary', {'count': dates.length, 'until': friendlyDate(context, dates.last)}),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Form(
      key: formKey,
      // Les erreurs se mettent à jour pendant la saisie
      autovalidateMode: AutovalidateMode.onUserInteraction,
      // SingleChildScrollView (et non ListView) : tous les champs restent construits, donc tous validés
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('post_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(context.tr('post_subtitle'), style: TextStyle(color: muted)),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: context.tr('section_route'),
            child: Row(children: [
              Expanded(
                child: Column(children: [
                  TextFormField(
                    controller: from,
                    textInputAction: TextInputAction.next,
                    decoration: deco('departure', Icons.trip_origin),
                    validator: (v) => t(Validators.place(v)),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: to,
                    textInputAction: TextInputAction.next,
                    decoration: deco('destination', Icons.location_on_outlined),
                    validator: (v) => t(Validators.destination(v, from.text)),
                  ),
                ]),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                  tooltip: context.tr('swap'), onPressed: swapPlaces, icon: const Icon(Icons.swap_vert)),
            ]),
          ),
          SectionCard(
            title: context.tr('section_when'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: dateCtrl,
                    readOnly: true,
                    onTap: pickDate,
                    decoration: deco('date', Icons.calendar_today_outlined),
                    validator: (_) => date == null ? context.tr('v_pick_date') : null,
                  ),
                ),
                const SizedBox(width: 10),
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
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.repeat),
                title: Text(context.tr('repeat_title')),
                subtitle: Text(context.tr('repeat_subtitle')),
                value: repeat,
                onChanged: (v) => setState(() {
                  repeat = v;
                  if (v && days.isEmpty && date != null) days.add(date!.weekday);
                }),
              ),
              if (repeat) recurrence(),
            ]),
          ),
          SectionCard(
            title: context.tr('section_seats_price'),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: seats,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: context.tr('seats'),
                    prefixIcon: IconButton(icon: const Icon(Icons.remove), onPressed: () => stepSeats(-1)),
                    suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => stepSeats(1)),
                  ),
                  validator: (v) => t(Validators.seats(v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: deco('price_dt', Icons.payments_outlined),
                  validator: (v) => t(Validators.price(v)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.publish),
            label: Text(context.tr('publish')),
          ),
        ]),
      ),
    );
  }
}
