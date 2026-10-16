import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final dest = TextEditingController();
  final price = TextEditingController();
  final seats = TextEditingController();
  DateTime? date;
  List rides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    final q = <String, String>{
      if (dest.text.trim().isNotEmpty) 'destination': dest.text.trim(),
      if (date != null) 'date': fmtDate(date!),
      if (price.text.trim().isNotEmpty) 'maxPrice': price.text.trim(),
      if (seats.text.trim().isNotEmpty) 'minSeats': seats.text.trim(),
    };
    await guard(context, () async => rides = await Api.searchRides(q));
    if (mounted) setState(() => loading = false);
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> book(Map r) async {
    if (await guard(context, () => Api.book(r['id']))) {
      if (mounted) toast(context, 'Demande envoyée au conducteur');
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(controller: dest, decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.place), border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(date == null ? 'Date' : fmtDate(date!)),
            )),
            if (date != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => date = null)),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix max dt', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Places min', border: OutlineInputBorder(), isDense: true))),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: load, icon: const Icon(Icons.search), label: const Text('Rechercher'))),
        ]),
      ),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : rides.isEmpty
                ? const Center(child: Text('Aucun trajet trouvé'))
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView.builder(
                      itemCount: rides.length,
                      itemBuilder: (_, i) {
                        final r = rides[i];
                        final mine = r['myBooking'];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              RideInfo(r),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: mine != null
                                    ? statusChip(mine)
                                    : FilledButton(onPressed: () => book(r), child: const Text('Demander une place')),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}
