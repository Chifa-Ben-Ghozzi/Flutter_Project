import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';

class MyRidesScreen extends StatefulWidget {
  const MyRidesScreen({super.key});
  @override
  State<MyRidesScreen> createState() => _MyRidesScreenState();
}

class _MyRidesScreenState extends State<MyRidesScreen> {
  List rides = [];
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

  Widget card(Map r) {
    final upcoming = r['status'] == 'open' && !isPast(r);
    final bookings = (r['bookings'] as List).where((b) => b['status'] != 'cancelled' || !upcoming).toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: RideInfo(r)),
            statusChip(r['status']),
          ]),
          if (bookings.isNotEmpty) const Divider(),
          ...bookings.map((b) {
            final p = b['passenger'] ?? {};
            final pending = b['status'] == 'pending' && upcoming;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person),
              title: Text(p['name'] ?? ''),
              subtitle: Text(p['phone'] ?? ''),
              trailing: pending
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => act(() => Api.respond(b['id'], true))),
                      IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => act(() => Api.respond(b['id'], false))),
                    ])
                  : statusChip(b['status']),
            );
          }),
          if (upcoming)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Annuler ce trajet ?'),
                      content: const Text('Les réservations seront annulées.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui')),
                      ],
                    ),
                  );
                  if (ok == true) act(() => Api.cancelRide(r['id']));
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Annuler le trajet', style: TextStyle(color: Colors.red)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget list(List items, String empty) => items.isEmpty
      ? Center(child: Text(empty))
      : RefreshIndicator(onRefresh: load, child: ListView(children: items.map((r) => card(r)).toList()));

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final upcoming = rides.where((r) => r['status'] == 'open' && !isPast(r)).toList();
    final history = rides.where((r) => !(r['status'] == 'open' && !isPast(r))).toList();
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'À venir'), Tab(text: 'Historique')]),
        Expanded(child: TabBarView(children: [
          list(upcoming, 'Aucun trajet à venir'),
          list(history, 'Aucun historique'),
        ])),
      ]),
    );
  }
}
