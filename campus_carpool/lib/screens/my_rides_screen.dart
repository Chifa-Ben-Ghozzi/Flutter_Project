import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';
import '../repositories/booking_repository.dart';
import '../repositories/ride_repository.dart';

class MyRidesScreen extends StatefulWidget {
  const MyRidesScreen({super.key});
  @override
  State<MyRidesScreen> createState() => _MyRidesScreenState();
}

class _MyRidesScreenState extends State<MyRidesScreen> {
  List<Ride> rides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await guard(context, () async => rides = await RideRepository.myRides());
    if (mounted) setState(() => loading = false);
  }

  Future<void> act(Future<void> Function() f) async {
    if (await guard(context, f)) load();
  }

  Future<void> confirmCancel(Ride r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.tr('cancel_ride_q')),
        content: Text(c.tr('cancel_ride_text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('no'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.tr('yes'))),
        ],
      ),
    );
    if (ok == true) act(() => RideRepository.cancel(r.id));
  }

  Widget card(Ride r) {
    final upcoming = r.isUpcoming;
    final bookings = r.bookings.where((b) => b.status != 'cancelled' || !upcoming).toList();
    final status = r.isCancelled ? 'cancelled' : (r.isCompleted || r.isPast ? 'done' : 'open');
    final canRate = !upcoming && !r.isCancelled && bookings.any((b) => b.status == 'accepted');
    return RideCard(
      r,
      showDriver: false,
      status: status,
      onTap: () async {
        if (await openRide(context, r.id)) load();
      },
      footer: bookings.isEmpty && !upcoming && !canRate
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (bookings.isNotEmpty) ...[
                Text(
                  context.tr('driver_requests').toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                ...bookings.map((b) {
                  final pending = b.status == 'pending' && upcoming;
                  return PassengerRequest(
                    b.passenger ?? AppUser(id: b.passengerId, name: '?'),
                    b.status,
                    onAccept: pending ? () => act(() => BookingRepository.respond(b.id, true)) : null,
                    onDecline: pending ? () => act(() => BookingRepository.respond(b.id, false)) : null,
                  );
                }),
              ],
              if (canRate)
                InfoLine(Icons.star_rounded, context.tr('tap_to_rate_passengers'), color: Colors.amber.shade800),
              if (upcoming)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: statusColor(context, 'declined')),
                    onPressed: () => confirmCancel(r),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.tr('cancel_ride')),
                  ),
                ),
            ]),
    );
  }

  Widget list(List<Ride> items, String emptyKey) => RefreshIndicator(
        onRefresh: load,
        child: items.isEmpty
            ? EmptyState(Icons.directions_car_outlined, context.tr(emptyKey))
            : ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 100),
                itemCount: items.length,
                itemBuilder: (_, i) => FadeSlideIn(index: i, child: card(items[i])),
              ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList();
    final upcoming = rides.where((r) => r.isUpcoming).toList();
    final history = rides.where((r) => !r.isUpcoming).toList();
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [
          Tab(text: '${context.tr('upcoming')} (${upcoming.length})'),
          Tab(text: context.tr('history')),
        ]),
        Expanded(
          child: TabBarView(children: [
            list(upcoming, 'no_upcoming_rides'),
            list(history, 'no_history'),
          ]),
        ),
      ]),
    );
  }
}
