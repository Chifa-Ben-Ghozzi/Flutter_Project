import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';

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
  List<Ride> rides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    dest.dispose();
    price.dispose();
    seats.dispose();
    super.dispose();
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

  Future<void> book(Ride r) async {
    final msg = context.tr('toast_request_sent');
    if (await guard(context, () => Api.book(r.id))) {
      if (mounted) toast(context, msg);
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(
            controller: dest,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: context.tr('destination'),
              prefixIcon: const Icon(Icons.place),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(date == null ? context.tr('date') : fmtDate(date!)),
              ),
            ),
            if (date != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => date = null)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('max_price'), border: const OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: seats,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('min_seats'), border: const OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: load, icon: const Icon(Icons.search), label: Text(context.tr('search_btn'))),
          ),
        ]),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: loading
              ? const SkeletonList()
              : RefreshIndicator(
                  onRefresh: load,
                  child: rides.isEmpty
                      ? EmptyState(Icons.search_off, context.tr('no_rides_found'))
                      : ListView.builder(
                          itemCount: rides.length,
                          itemBuilder: (_, i) => FadeSlideIn(index: i, child: card(rides[i])),
                        ),
                ),
        ),
      ),
    ]);
  }

  Widget card(Ride r) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            if (await openRide(context, r.id)) load();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RideInfo(r),
              const SizedBox(height: 8),
              Row(children: [
                Text(context.tr('see_details'), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                const Spacer(),
                r.myBookingStatus != null
                    ? statusChip(context, r.myBookingStatus!)
                    : FilledButton(onPressed: () => book(r), child: Text(context.tr('request_seat'))),
              ]),
            ]),
          ),
        ),
      );
}
