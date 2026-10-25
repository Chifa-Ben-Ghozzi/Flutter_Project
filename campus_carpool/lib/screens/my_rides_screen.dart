import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';

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
    await guard(context, () async => rides = await Api.myRides());
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
    if (ok == true) act(() => Api.cancelRide(r.id));
  }

  Widget card(Ride r) {
    final upcoming = r.isUpcoming;
    final bookings = r.bookings.where((b) => b.status != 'cancelled' || !upcoming).toList();
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (await openRide(context, r.id)) load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: RideInfo(r)),
              statusChip(context, r.isCancelled ? 'cancelled' : (r.isPast ? 'done' : 'open')),
            ]),
            if (bookings.isNotEmpty) const Divider(),
            ...bookings.map((b) {
              final p = b.passenger ?? AppUser(id: b.passengerId, name: '?');
              final pending = b.status == 'pending' && upcoming;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: avatar(p, radius: 16),
                title: Text(p.name),
                subtitle: RatingLabel(p),
                trailing: pending
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: context.tr('accept'),
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => act(() => Api.respond(b.id, true)),
                        ),
                        IconButton(
                          tooltip: context.tr('decline'),
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => act(() => Api.respond(b.id, false)),
                        ),
                      ])
                    : statusChip(context, b.status),
              );
            }),
            if (upcoming)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => confirmCancel(r),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(context.tr('cancel_ride'), style: const TextStyle(color: Colors.red)),
                ),
              ),
            if (!upcoming && !r.isCancelled && bookings.any((b) => b.status == 'accepted'))
              Text('⭐ ${context.tr('tap_to_rate_passengers')}', style: TextStyle(color: primary)),
          ]),
        ),
      ),
    );
  }

  Widget list(List<Ride> items, String emptyKey) => RefreshIndicator(
        onRefresh: load,
        child: items.isEmpty
            ? EmptyState(Icons.directions_car_outlined, context.tr(emptyKey))
            : ListView.builder(
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
