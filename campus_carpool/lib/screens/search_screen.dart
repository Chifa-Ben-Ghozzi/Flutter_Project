import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../repositories/booking_repository.dart';
import '../repositories/ride_repository.dart';
import '../widgets.dart';
import 'alerts_screen.dart';
import 'ride_details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final from = TextEditingController();
  final dest = TextEditingController();
  DateTime? date;
  double? maxPrice;
  int? minSeats;
  List<Ride> rides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    from.dispose();
    dest.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    final q = <String, String>{
      if (from.text.trim().isNotEmpty) 'from': from.text.trim(),
      if (dest.text.trim().isNotEmpty) 'destination': dest.text.trim(),
      if (date != null) 'date': fmtDate(date!),
      if (maxPrice != null) 'maxPrice': fmtPrice(maxPrice!),
      if (minSeats != null) 'minSeats': '$minSeats',
    };
    await guard(context, () async => rides = await RideRepository.search(q));
    if (mounted) setState(() => loading = false);
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() => date = d);
      load();
    }
  }

  void swap() => setState(() {
        final t = from.text;
        from.text = dest.text;
        dest.text = t;
      });

  Future<void> book(Ride r) async {
    final msg = context.tr('toast_request_sent');
    if (await guard(context, () => BookingRepository.request(r.id))) {
      if (mounted) toast(context, msg);
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('search_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(context.tr('search_subtitle'), style: TextStyle(color: muted)),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: searchCard()),
        const SizedBox(height: 12),
        filters(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child:
              FilledButton.icon(onPressed: load, icon: const Icon(Icons.search), label: Text(context.tr('search_btn'))),
        ),
        AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: results()),
      ]),
    );
  }

  /// Départ et destination dans une seule carte, reliés comme un itinéraire, avec un bouton pour inverser.
  Widget searchCard() {
    final scheme = Theme.of(context).colorScheme;
    InputDecoration deco(String key) => InputDecoration(
          hintText: context.tr(key),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(children: [
          Column(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.primary, width: 2.5)),
            ),
            Container(width: 2, height: 34, color: scheme.outlineVariant),
            Icon(Icons.location_on, size: 18, color: scheme.primary),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(children: [
              TextField(
                controller: from,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => load(),
                decoration: deco('departure'),
              ),
              const Divider(),
              TextField(
                controller: dest,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => load(),
                decoration: deco('destination'),
              ),
            ]),
          ),
          IconButton(tooltip: context.tr('swap'), onPressed: swap, icon: const Icon(Icons.swap_vert)),
        ]),
      ),
    );
  }

  /// Filtres en "chips" : date, prix maximum, places minimum. Ils s'appliquent tout de suite.
  Widget filters() {
    Widget menu<T>({
      required IconData icon,
      required String label,
      required bool active,
      required List<(T?, String)> options,
      required void Function(T?) onSelected,
    }) =>
        PopupMenuButton<(T?, String)>(
          onSelected: (o) {
            onSelected(o.$1);
            load();
          },
          itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o, child: Text(o.$2))],
          child: Chip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            backgroundColor: active ? Theme.of(context).colorScheme.secondaryContainer : null,
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        InputChip(
          avatar: const Icon(Icons.calendar_today, size: 18),
          label: Text(date == null ? context.tr('date') : friendlyDate(context, date!)),
          selected: date != null,
          showCheckmark: false,
          onPressed: pickDate,
          onDeleted: date == null
              ? null
              : () {
                  setState(() => date = null);
                  load();
                },
        ),
        const SizedBox(width: 8),
        menu<double>(
          icon: Icons.payments_outlined,
          label: maxPrice == null
              ? context.tr('max_price')
              : context.tr('max_price_value', {'price': fmtPrice(maxPrice!)}),
          active: maxPrice != null,
          options: [
            (null, context.tr('any')),
            for (final p in [3.0, 5.0, 8.0, 10.0]) (p, context.tr('max_price_value', {'price': fmtPrice(p)})),
          ],
          onSelected: (v) => setState(() => maxPrice = v),
        ),
        const SizedBox(width: 8),
        menu<int>(
          icon: Icons.event_seat_outlined,
          label: minSeats == null ? context.tr('min_seats') : context.tr('min_seats_value', {'n': minSeats}),
          active: minSeats != null,
          options: [
            (null, context.tr('any')),
            for (final n in [1, 2, 3, 4]) (n, context.tr('min_seats_value', {'n': n})),
          ],
          onSelected: (v) => setState(() => minSeats = v),
        ),
      ]),
    );
  }

  Widget results() {
    if (loading) return const SizedBox(key: ValueKey('loading'), height: 320, child: SkeletonList(count: 2));
    return Column(key: const ValueKey('results'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(
          context.tr(rides.length == 1 ? 'offer_count_one' : 'offer_count_other', {'count': rides.length}),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      // Alerte : être prévenu des prochains trajets de cette recherche
      if (from.text.trim().isNotEmpty || dest.text.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => showAlertForm(context, from: from.text, to: dest.text, maxPrice: maxPrice),
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(context.tr('alert_create_from_search')),
          ),
        ),
      if (rides.isEmpty)
        SizedBox(height: 280, child: EmptyState(Icons.search_off, context.tr('no_rides_found')))
      else
        for (final (i, r) in rides.indexed) FadeSlideIn(index: i, child: card(r)),
    ]);
  }

  Widget card(Ride r) => RideCard(
        r,
        status: r.myBookingStatus,
        onTap: () async {
          if (await openRide(context, r.id)) load();
        },
        footer: r.myBookingStatus != null
            ? null
            : SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => book(r),
                  child: Text(context.tr('request_seat')),
                ),
              ),
      );
}
