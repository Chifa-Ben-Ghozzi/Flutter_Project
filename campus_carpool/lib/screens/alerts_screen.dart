import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../repositories/alert_repository.dart';
import '../validators.dart';
import '../widgets.dart';

/// Mes alertes de trajet : la liste, la suppression et la création (formulaire avec validators).
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<RideAlert> alerts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await guard(context, () async => alerts = await AlertRepository.mine());
    if (mounted) setState(() => loading = false);
  }

  Future<void> delete(RideAlert a) async {
    final msg = context.tr('alert_deleted');
    if (await guard(context, () => AlertRepository.delete(a.id))) {
      if (mounted) toast(context, msg);
      load();
    }
  }

  Future<void> create() async {
    if (await showAlertForm(context)) load();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('alerts'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add_alert),
        label: Text(context.tr('alert_new')),
      ),
      body: loading
          ? const SkeletonList(count: 3)
          : RefreshIndicator(
              onRefresh: load,
              child: alerts.isEmpty
                  ? EmptyState(Icons.notifications_off_outlined, context.tr('no_alerts'))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: Text(context.tr('alerts_subtitle'), style: TextStyle(color: muted)),
                      ),
                      for (final (i, a) in alerts.indexed)
                        FadeSlideIn(
                          index: i,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                              leading: const CircleAvatar(child: Icon(Icons.notifications_active_outlined)),
                              title: Text(alertRoute(context, a), style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(a.maxPrice == null
                                  ? context.tr('alert_any_price')
                                  : context.tr('alert_max_price', {'price': fmtPrice(a.maxPrice!)})),
                              trailing: IconButton(
                                tooltip: context.tr('delete'),
                                onPressed: () => delete(a),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                        ),
                    ]),
            ),
    );
  }
}

/// "Ariana → Esprit", un lieu vide s'affichant "Partout".
String alertRoute(BuildContext context, RideAlert a) {
  String place(String p) => p.isEmpty ? context.tr('alert_anywhere') : p;
  return '${place(a.from)} → ${place(a.to)}';
}

/// Formulaire de création d'une alerte (pré-rempli depuis la recherche). Renvoie true si l'alerte est créée.
Future<bool> showAlertForm(BuildContext context, {String from = '', String to = '', double? maxPrice}) async {
  final formKey = GlobalKey<FormState>();
  final fromCtrl = TextEditingController(text: from);
  final toCtrl = TextEditingController(text: to);
  final priceCtrl = TextEditingController(text: maxPrice == null ? '' : fmtPrice(maxPrice));
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.tr('alert_new')),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(c.tr('alert_create_hint'), style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextFormField(
            controller: fromCtrl,
            decoration: InputDecoration(labelText: c.tr('departure'), prefixIcon: const Icon(Icons.trip_origin)),
            // Au moins un des deux lieux
            validator: (_) => fromCtrl.text.trim().isEmpty && toCtrl.text.trim().isEmpty ? c.tr('v_alert_place') : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: toCtrl,
            decoration:
                InputDecoration(labelText: c.tr('destination'), prefixIcon: const Icon(Icons.location_on_outlined)),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                InputDecoration(labelText: c.tr('max_price_optional'), prefixIcon: const Icon(Icons.payments_outlined)),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null; // facultatif
              final key = Validators.price(v);
              return key == null ? null : c.tr(key);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('cancel'))),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(c, true);
          },
          child: Text(c.tr('create')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final done = context.tr('alert_created');
  final price = priceCtrl.text.trim().isEmpty ? null : Validators.parsePrice(priceCtrl.text);
  final created =
      await guard(context, () => AlertRepository.add(from: fromCtrl.text, to: toCtrl.text, maxPrice: price));
  if (created && context.mounted) toast(context, done);
  return created;
}
