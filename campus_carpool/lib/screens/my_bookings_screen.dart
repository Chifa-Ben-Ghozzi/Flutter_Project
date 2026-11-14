import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'ride_details_screen.dart';
import '../repositories/booking_repository.dart';

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
    await guard(context, () async => bookings = await BookingRepository.myBookings());
    if (mounted) setState(() => loading = false);
  }

  Widget card(Booking b) {
    final ride = b.ride!;
    final primary = Theme.of(context).colorScheme.primary;
    final accepted = b.status == 'accepted';
    final rate = accepted && (ride.isCompleted || ride.isPast) && !ride.isCancelled;
    return RideCard(
      ride,
      status: b.status,
      onTap: () async {
        if (await openRide(context, ride.id)) load();
      },
      footer: !accepted && !b.isUpcoming
          ? null
          : Row(children: [
              if (rate)
                Expanded(
                    child: InfoLine(Icons.star_rounded, context.tr('tap_to_rate_driver'), color: Colors.amber.shade800))
              else if (accepted)
                Expanded(child: InfoLine(Icons.call_outlined, context.tr('tap_to_call_driver'), color: primary))
              else
                const Spacer(),
              if (b.isUpcoming)
                IconButton(
                  tooltip: context.tr('msg_send_message'),
                  onPressed: () => openChat(context, b.id),
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
              if (b.isUpcoming)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: statusColor(context, 'declined')),
                  onPressed: () async {
                    if (await guard(context, () => BookingRepository.cancel(b.id))) load();
                  },
                  icon: const Icon(Icons.close),
                  label: Text(context.tr('cancel')),
                ),
            ]),
    );
  }

  Widget list(List<Booking> items, String emptyKey) => RefreshIndicator(
        onRefresh: load,
        child: items.isEmpty
            ? EmptyState(Icons.event_seat_outlined, context.tr(emptyKey))
            : ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 100),
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
