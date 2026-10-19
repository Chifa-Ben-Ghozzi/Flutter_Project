import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Booking> bookings = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await guard(context, () async => bookings = await Api.myBookings());
    if (mounted) setState(() => loading = false);
  }

  Widget card(Booking b) {
    final ride = b.ride!;
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (await openRide(context, ride.id)) load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: RideInfo(ride)),
              statusChip(context, b.status),
            ]),
            if (b.status == 'accepted' && ride.isPast && !ride.isCancelled)
              Text('⭐ ${context.tr('tap_to_rate_driver')}', style: TextStyle(color: primary))
            else if (b.status == 'accepted')
              Text('📞 ${context.tr('tap_to_call_driver')}', style: TextStyle(color: primary)),
            if (b.isUpcoming)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () async {
                    if (await guard(context, () => Api.cancelBooking(b.id))) load();
                  },
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: Text(context.tr('cancel'), style: const TextStyle(color: Colors.red)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget list(List<Booking> items, String emptyKey) => RefreshIndicator(
        onRefresh: load,
        child: items.isEmpty
            ? EmptyState(Icons.event_seat_outlined, context.tr(emptyKey))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => FadeSlideIn(index: i, child: card(items[i])),
              ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList();
    final valid = bookings.where((b) => b.ride != null).toList();
    final upcoming = valid.where((b) => b.isUpcoming).toList();
    final history = valid.where((b) => !b.isUpcoming).toList();
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [
          Tab(text: '${context.tr('upcoming')} (${upcoming.length})'),
          Tab(text: context.tr('history')),
        ]),
        Expanded(
          child: TabBarView(children: [
            list(upcoming, 'no_upcoming_bookings'),
            list(history, 'no_history'),
          ]),
        ),
      ]),
    );
  }
}
