import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List bookings = [];
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

  bool isUpcoming(Map b) => ['pending', 'accepted'].contains(b['status']) && !isPast(b['ride']);

  Widget card(Map b) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: RideInfo(b['ride'])), statusChip(b['status'])]),
            if (isUpcoming(b))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    if (await guard(context, () => Api.cancelBooking(b['id']))) load();
                  },
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text('Annuler', style: TextStyle(color: Colors.red)),
                ),
              ),
          ]),
        ),
      );

  Widget list(List items, String empty) => items.isEmpty
      ? Center(child: Text(empty))
      : RefreshIndicator(onRefresh: load, child: ListView(children: items.map((b) => card(b)).toList()));

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final upcoming = bookings.where((b) => isUpcoming(b)).toList();
    final history = bookings.where((b) => !isUpcoming(b)).toList();
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'À venir'), Tab(text: 'Historique')]),
        Expanded(child: TabBarView(children: [
          list(upcoming, 'Aucune réservation à venir'),
          list(history, 'Aucun historique'),
        ])),
      ]),
    );
  }
}
