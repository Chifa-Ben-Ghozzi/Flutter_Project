import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../routes.dart';
import '../widgets.dart';
import '../widgets/ride_map.dart';
import '../repositories/booking_repository.dart';
import '../repositories/review_repository.dart';
import '../repositories/ride_repository.dart';
import '../repositories/user_repository.dart';

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
    await guard(context, () async => d = await RideRepository.details(widget.rideId));
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
                      child: TextButton.icon(
                          onPressed: load, icon: const Icon(Icons.refresh), label: Text(context.tr('retry'))),
                    )
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                        header(),
                        // Après le trajet, noter est l'action principale : juste sous l'en-tête
                        if (d!.toRate.isNotEmpty) rateCard(),
                        if (d!.ride.hasCoords)
                          Padding(padding: const EdgeInsets.only(bottom: 12), child: RideMap(d!.ride)),
                        driverCard(),
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
    final scheme = Theme.of(context).colorScheme;
    final status = r.isCancelled ? 'cancelled' : (d!.finished ? 'done' : 'open');
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.time, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 6),
              Text(
                friendlyDate(context, r.dateTime),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            PricePill(r.price, large: true),
            const SizedBox(height: 4),
            Text(context.tr('per_seat'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 20),
        Hero(
          tag: 'ride-title-${r.id}',
          child: Material(type: MaterialType.transparency, child: RouteTimeline(r.from, r.to, fontSize: 18)),
        ),
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: InfoLine(
                  Icons.event_seat_outlined, context.tr('seats_free', {'left': r.seatsLeft, 'total': r.seats}))),
          statusChip(context, status),
        ]),
      ]),
    );
  }

  Widget driverCard() {
    final driver = d!.driver;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SectionCard(
      title: context.tr('driver'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showUserProfile(context, driver.id),
          child: Row(children: [
            avatar(driver, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  d!.isDriver ? context.tr('name_you', {'name': driver.name}) : driver.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                RatingLabel(driver),
                if (driver.hasCar) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.directions_car_outlined, size: 16, color: muted),
                    const SizedBox(width: 6),
                    Flexible(child: Text('${driver.carModel} · ${driver.carPlate}', style: TextStyle(color: muted))),
                  ]),
                ],
              ]),
            ),
            Icon(Icons.chevron_right, color: muted),
          ]),
        ),
        if (d!.iAmAccepted && !d!.ride.isCancelled) ...[
          const SizedBox(height: 14),
          ContactButtons(driver,
              message: context.tr('wa_to_driver',
                  {'name': driver.name, 'route': d!.ride.route, 'date': d!.ride.date, 'time': d!.ride.time})),
        ] else if (!d!.isDriver && d!.myBooking?.status == 'pending') ...[
          const SizedBox(height: 12),
          Text(context.tr('call_after_accept'), style: TextStyle(color: muted)),
        ],
      ]),
    );
  }

  Widget passengersCard() {
    final list = d!.ride.bookings.where((b) => b.status != 'cancelled' || !d!.isOpen).toList();
    return SectionCard(
      title: context.tr(d!.isDriver ? 'requests_and_passengers' : 'passengers'),
      child: list.isEmpty
          ? Text(context.tr('no_passengers'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          : Column(children: [
              for (final (i, b) in list.indexed) ...[
                if (i > 0) const Divider(height: 16),
                passengerTile(b),
              ],
            ]),
    );
  }

  Widget passengerTile(Booking b) {
    final p = b.passenger ?? AppUser(id: b.passengerId, name: '?');
    final pending = d!.isDriver && d!.isOpen && b.status == 'pending';
    return PassengerRequest(
      p,
      b.status,
      onTap: () => showUserProfile(context, p.id),
      onAccept: pending ? () => act(() => BookingRepository.respond(b.id, true), 'toast_accepted') : null,
      onDecline: pending ? () => act(() => BookingRepository.respond(b.id, false), 'toast_declined') : null,
      below: d!.isDriver && b.status == 'accepted' && !d!.ride.isCancelled
          ? ContactButtons(p,
              message: context.tr('wa_to_passenger',
                  {'name': p.name, 'route': d!.ride.route, 'date': d!.ride.date, 'time': d!.ride.time}))
          : null,
    );
  }

  Widget rateCard() => SectionCard(
        title: context.tr('how_was_ride'),
        color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        child: Column(children: [
          for (final u in d!.toRate)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                avatar(u, radius: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () async {
                    if (await rateDialog(context, d!.ride.id, u)) {
                      changed = true;
                      load();
                    }
                  },
                  icon: const Icon(Icons.star_rounded, size: 18),
                  label: Text(context.tr('rate')),
                ),
              ]),
            ),
        ]),
      );

  Widget? actions() {
    final r = d!.ride;
    if (!d!.isOpen) return null;
    Widget bar(Widget child) =>
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: child));
    final danger = OutlinedButton.styleFrom(foregroundColor: Colors.red);

    if (d!.isDriver) {
      return bar(OutlinedButton.icon(
        style: danger,
        onPressed: () async {
          if (await confirm('cancel_ride_q', 'cancel_ride_text')) {
            act(() => RideRepository.cancel(r.id), 'toast_ride_cancelled');
          }
        },
        icon: const Icon(Icons.delete_outline),
        label: Text(context.tr('cancel_ride')),
      ));
    }
    final b = d!.myBooking;
    if (b?.status == 'accepted') {
      return bar(Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              if (await confirm('end_ride_q', 'end_ride_text')) {
                act(() => RideRepository.end(r.id, b!.id), 'toast_ride_ended');
              }
            },
            icon: const Icon(Icons.flag_outlined),
            label: Text(context.tr('end_ride')),
          ),
        ),
        TextButton.icon(
          style: danger,
          onPressed: () async {
            if (await confirm('cancel_booking_q', 'cancel_booking_text')) {
              act(() => BookingRepository.cancel(b!.id), 'toast_booking_cancelled');
            }
          },
          icon: const Icon(Icons.close),
          label: Text(context.tr('cancel_seat')),
        ),
      ]));
    }
    if (b != null && b.isActive) {
      return bar(OutlinedButton.icon(
        style: danger,
        onPressed: () async {
          if (await confirm('cancel_booking_q', 'cancel_booking_text')) {
            act(() => BookingRepository.cancel(b.id), 'toast_booking_cancelled');
          }
        },
        icon: const Icon(Icons.close),
        label: Text(context.tr(b.status == 'pending' ? 'cancel_request' : 'cancel_seat')),
      ));
    }
    if (r.seatsLeft < 1) return bar(FilledButton(onPressed: null, child: Text(context.tr('full'))));
    return bar(FilledButton.icon(
      onPressed: () => act(() => BookingRepository.request(r.id), 'toast_request_sent'),
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
            decoration: InputDecoration(labelText: c.tr('comment_optional')),
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
  final ok = await guard(context, () => ReviewRepository.add(rideId, user.id, stars, comment.text.trim()));
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
        future: UserRepository.publicUser(userId),
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
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(c.tr('no_reviews'), style: TextStyle(color: muted))),
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
