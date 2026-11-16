import 'package:flutter/material.dart';
import '../l10n.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../repositories/booking_repository.dart';
import '../repositories/connection_repository.dart';
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
  // Itinéraires avec correspondance, proposés quand il n'y a aucun trajet direct
  List<RideConnection> connections = [];
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
    await guard(context, () async {
      rides = await RideRepository.search(q);
      connections = const [];
      // Aucun trajet direct entre deux lieux : on cherche deux covoiturages qui s'enchaînent
      if (rides.isEmpty && q.containsKey('from') && q.containsKey('destination')) {
        connections = await ConnectionRepository.find(
          from: q['from']!,
          to: q['destination']!,
          date: q['date'],
          maxPrice: maxPrice,
          minSeats: minSeats,
        );
      }
    });
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

  /// Demande une place sur chacun des deux trajets d'une correspondance (ceux pas encore demandés).
  Future<void> bookConnection(RideConnection c) async {
    final msg = context.tr('conn_requested');
    var ok = true;
    for (final r in [c.first, c.second]) {
      if (ok && r.myBookingStatus == null) ok = await guard(context, () => BookingRepository.request(r.id));
    }
    if (ok && mounted) toast(context, msg);
    load();
  }

  Future<void> book(Ride r) async {
    final msg = context.tr('toast_request_sent');
    if (await guard(context, () => BookingRepository.request(r.id))) {
      if (mounted) toast(context, msg);
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().user?.name.trim() ?? '';
    final firstName = name.split(' ').first;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        // En-tête au dégradé de la marque : salutation, titre, recherche et bouton
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: GradientPanel(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (firstName.isNotEmpty)
                Text(context.tr('hello_name', {'name': firstName}),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(context.tr('search_title'),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const SizedBox(height: 2),
              Text(context.tr('search_subtitle'), style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
              const SizedBox(height: 16),
              searchCard(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.seed),
                  onPressed: load,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(context.tr('search_btn')),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        filters(),
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
    return Container(
      decoration: BoxDecoration(color: AppTheme.card(scheme), borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(children: [
          Column(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.primary, width: 2.5)),
            ),
            Container(width: 2, height: 34, color: scheme.outlineVariant),
            Icon(Icons.location_on_rounded, size: 18, color: AppTheme.violet),
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
          IconButton.filledTonal(
              tooltip: context.tr('swap'), onPressed: swap, icon: const Icon(Icons.swap_vert_rounded)),
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
      SectionHeader(
        context.tr(rides.length == 1 ? 'offer_count_one' : 'offer_count_other', {'count': rides.length}),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
      if (rides.isEmpty && connections.isNotEmpty) ...[
        SectionHeader(context.tr('conn_title'), padding: const EdgeInsets.fromLTRB(20, 10, 20, 2)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text(context.tr('conn_hint'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
        ),
        for (final (i, c) in connections.indexed) FadeSlideIn(index: i, child: connectionCard(c)),
      ] else if (rides.isEmpty)
        SizedBox(height: 280, child: EmptyState(Icons.search_off, context.tr('no_rides_found')))
      else
        for (final (i, r) in rides.indexed) FadeSlideIn(index: i, child: card(r)),
    ]);
  }

  /// "25 min" ou "1 h 05".
  static String fmtWait(Duration d) =>
      d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h ${two(d.inMinutes % 60)}';

  /// Carte d'un itinéraire avec correspondance : les deux trajets, le lieu et le temps d'attente, le prix total.
  Widget connectionCard(RideConnection c) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    // Un des deux trajets ; le toucher ouvre ses détails
    Widget leg(Ride r) => InkWell(
          onTap: () async {
            if (await openRide(context, r.id)) load();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
            child: Row(children: [
              SizedBox(
                width: 54,
                child: Text(r.time, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.route,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (r.driver != null) r.driver!.name,
                      '${fmtPrice(r.price)} dt',
                      context.tr('seats_left_of', {'left': r.seatsLeft, 'total': r.seats}),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ]),
              ),
              if (r.myBookingStatus != null) statusChip(context, r.myBookingStatus!),
              Icon(Icons.chevron_right, color: muted, size: 20),
            ]),
          ),
        );

    final allRequested = c.first.myBookingStatus != null && c.second.myBookingStatus != null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 16, 2),
          child: Row(children: [
            Icon(Icons.alt_route_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(friendlyDate(context, c.first.dateTime),
                  style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            PricePill(c.price),
          ]),
        ),
        leg(c.first),
        // Bandeau de correspondance : où changer de voiture, et combien de temps on attend
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.transfer_within_a_station_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('conn_stop', {
                  'place': c.via,
                  'arrival': '${two(c.arrival.hour)}:${two(c.arrival.minute)}',
                  'wait': fmtWait(c.wait),
                }),
                style: TextStyle(color: scheme.primary, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        leg(c.second),
        if (!allRequested)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => bookConnection(c),
              child: Text(context.tr('conn_request_both')),
            ),
          )
        else
          const SizedBox(height: 6),
      ]),
    );
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
