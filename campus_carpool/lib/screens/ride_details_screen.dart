import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../routes.dart';
import '../widgets.dart';
import '../widgets/ride_map.dart';

/// Ouvre l'écran de détails (route nommée '/ride' avec l'id du trajet en argument).
/// Renvoie true si quelque chose a changé, pour rafraîchir la liste appelante.
Future<bool> openRide(BuildContext c, String rideId) async =>
    await Navigator.pushNamed<bool>(c, AppRoutes.rideDetails, arguments: rideId) ?? false;

class RideDetailsScreen extends StatefulWidget {
  final String rideId;
  const RideDetailsScreen({super.key, required this.rideId});
  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  RideDetails? d;
  bool loading = true;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await guard(context, () async => d = await Api.rideDetails(widget.rideId));
    if (mounted) setState(() => loading = false);
  }

  Future<void> act(Future<void> Function() f, String doneKey) async {
    final msg = context.tr(doneKey);
    if (await guard(context, f)) {
      changed = true;
      if (mounted) toast(context, msg);
      load();
    }
  }

  Future<bool> confirm(String titleKey, String textKey) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(c.tr(titleKey)),
          content: Text(c.tr(textKey)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('no'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.tr('yes'))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('ride_details'))),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: loading
              ? const SkeletonList(count: 3)
              : d == null
                  ? Center(
                      child: TextButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: Text(context.tr('retry'))),
                    )
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView(padding: const EdgeInsets.all(12), children: [
                        header(),
                        if (d!.ride.hasCoords) RideMap(d!.ride),
                        driverCard(),
                        if (d!.toRate.isNotEmpty) rateCard(),
                        passengersCard(),
                      ]),
                    ),
        ),
        bottomNavigationBar: d == null ? null : actions(),
      ),
    );
  }

  // ---------- Sections ----------

  Widget header() {
    final r = d!.ride;
    final status = r.isCancelled ? 'cancelled' : (d!.finished ? 'done' : 'open');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Hero(
                tag: 'ride-title-${r.id}',
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(r.route, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            statusChip(context, status),
          ]),
          const SizedBox(height: 12),
          info(Icons.calendar_today, context.tr('date_at_time', {'date': r.date, 'time': r.time})),
          info(Icons.payments_outlined, context.tr('price_per_seat', {'price': fmtPrice(r.price)})),
          info(Icons.event_seat, context.tr('seats_free', {'left': r.seatsLeft, 'total': r.seats})),
        ]),
      ),
    );
  }

  Widget info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Flexible(child: Text(text)),
        ]),
      );

  Widget sectionTitle(String key) => Text(
        context.tr(key),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      );

  Widget driverCard() {
    final driver = d!.driver;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle('driver'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: avatar(driver),
            title: Text(d!.isDriver ? context.tr('name_you', {'name': driver.name}) : driver.name),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RatingLabel(driver),
              if (driver.hasCar) Text('🚗 ${driver.carModel} · ${driver.carPlate}'),
            ]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showUserProfile(context, driver.id),
          ),
          if (d!.iAmAccepted && !d!.ride.isCancelled)
            ContactButtons(driver,
                message: context.tr('wa_to_driver', {'name': driver.name, 'route': d!.ride.route, 'date': d!.ride.date, 'time': d!.ride.time}))
          else if (!d!.isDriver && d!.myBooking?.status == 'pending')
            Text(context.tr('call_after_accept'), style: TextStyle(color: muted)),
        ]),
      ),
    );
  }

  Widget passengersCard() {
    final list = d!.ride.bookings.where((b) => b.status != 'cancelled' || !d!.isOpen).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(d!.isDriver ? 'requests_and_passengers' : 'passengers'),
          if (list.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(context.tr('no_passengers'))),
          ...list.map(passengerTile),
        ]),
      ),
    );
  }

  Widget passengerTile(Booking b) {
    final p = b.passenger ?? AppUser(id: b.passengerId, name: '?');
    final pending = d!.isDriver && d!.isOpen && b.status == 'pending';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: avatar(p, radius: 20),
        title: Text(p.name),
        subtitle: RatingLabel(p),
        onTap: () => showUserProfile(context, p.id),
        trailing: pending
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: context.tr('accept'),
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () => act(() => Api.respond(b.id, true), 'toast_accepted'),
                ),
                IconButton(
                  tooltip: context.tr('decline'),
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () => act(() => Api.respond(b.id, false), 'toast_declined'),
                ),
              ])
            : statusChip(context, b.status),
      ),
      if (d!.isDriver && b.status == 'accepted' && !d!.ride.isCancelled)
        Padding(
          padding: const EdgeInsets.only(left: 56, bottom: 8),
          child: ContactButtons(p,
              message: context.tr('wa_to_passenger', {'name': p.name, 'route': d!.ride.route, 'date': d!.ride.date, 'time': d!.ride.time})),
        ),
    ]);
  }

  Widget rateCard() => Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⭐ ${context.tr('how_was_ride')}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ...d!.toRate.map((u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: avatar(u, radius: 20),
                  title: Text(u.name),
                  trailing: FilledButton(
                    onPressed: () async {
                      if (await rateDialog(context, d!.ride.id, u)) {
                        changed = true;
                        load();
                      }
                    },
                    child: Text(context.tr('rate')),
                  ),
                )),
          ]),
        ),
      );

  Widget? actions() {
    final r = d!.ride;
    if (!d!.isOpen) return null;
    Widget bar(Widget child) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: child));
    final danger = OutlinedButton.styleFrom(foregroundColor: Colors.red);

    if (d!.isDriver) {
      return bar(OutlinedButton.icon(
        style: danger,
        onPressed: () async {
          if (await confirm('cancel_ride_q', 'cancel_ride_text')) act(() => Api.cancelRide(r.id), 'toast_ride_cancelled');
        },
        icon: const Icon(Icons.delete_outline),
        label: Text(context.tr('cancel_ride')),
      ));
    }
    final b = d!.myBooking;
    if (b != null && b.isActive) {
      return bar(OutlinedButton.icon(
        style: danger,
        onPressed: () async {
          if (await confirm('cancel_booking_q', 'cancel_booking_text')) act(() => Api.cancelBooking(b.id), 'toast_booking_cancelled');
        },
        icon: const Icon(Icons.close),
        label: Text(context.tr(b.status == 'pending' ? 'cancel_request' : 'cancel_seat')),
      ));
    }
    if (r.seatsLeft < 1) return bar(FilledButton(onPressed: null, child: Text(context.tr('full'))));
    return bar(FilledButton.icon(
      onPressed: () => act(() => Api.book(r.id), 'toast_request_sent'),
      icon: const Icon(Icons.event_seat),
      label: Text(context.tr('request_seat_price', {'price': fmtPrice(r.price)})),
    ));
  }
}

// ---------- Noter quelqu'un ----------

Future<bool> rateDialog(BuildContext context, String rideId, AppUser user) async {
  var stars = 5;
  final comment = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text(c.tr('rate_name', {'name': user.name})),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Stars(stars, size: 36, onChanged: (v) => setLocal(() => stars = v)),
          Text(c.tr('stars_$stars')),
          const SizedBox(height: 12),
          TextField(
            controller: comment,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(labelText: c.tr('comment_optional'), border: const OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.tr('send'))),
        ],
      ),
    ),
  );
  if (send != true || !context.mounted) return false;
  final thanks = context.tr('toast_thanks_review');
  final ok = await guard(context, () => Api.review(rideId, user.id, stars, comment.text.trim()));
  if (ok && context.mounted) toast(context, thanks);
  return ok;
}

// ---------- Profil public (note + avis) ----------

void showUserProfile(BuildContext context, String userId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.75,
      child: FutureBuilder<AppUser>(
        future: Api.publicUser(userId),
        builder: (c, snap) {
          if (snap.hasError) return Center(child: Text(c.tr('err_server')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final u = snap.data!;
          final muted = Theme.of(c).colorScheme.onSurfaceVariant;
          final isMe = c.watch<AuthProvider>().user?.id == u.id;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
            Center(child: avatar(u, radius: 40)),
            const SizedBox(height: 8),
            Center(
              child: Text(isMe ? c.tr('name_you', {'name': u.name}) : u.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Center(child: RatingLabel(u)),
            if (u.hasCar) Center(child: Text('🚗 ${u.carModel} · ${u.carPlate}')),
            const Divider(height: 32),
            Text(c.tr('reviews_count', {'n': u.ratingCount}), style: const TextStyle(fontWeight: FontWeight.bold)),
            if (u.reviews.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.tr('no_reviews'), style: TextStyle(color: muted))),
            ...u.reviews.map((r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(children: [
                    Stars(r.stars, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text(r.from, overflow: TextOverflow.ellipsis)),
                  ]),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (r.comment.isNotEmpty) Text(r.comment),
                    if (r.createdAt.length >= 10)
                      Text(r.createdAt.substring(0, 10), style: TextStyle(fontSize: 11, color: muted)),
                  ]),
                )),
          ]);
        },
      ),
    ),
  );
}
