import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'l10n.dart';
import 'models.dart';

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String fmtPrice(double p) => p == p.roundToDouble() ? p.toInt().toString() : p.toStringAsFixed(1);

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

/// Exécute un appel API en affichant l'erreur éventuelle (traduite). Retourne true si succès.
Future<bool> guard(BuildContext c, Future<void> Function() f) async {
  final l10n = c.read<L10n>();
  try {
    await f();
    return true;
  } on ApiException catch (e) {
    if (c.mounted) toast(c, l10n.trServer(e.message));
  } on NetworkException {
    if (c.mounted) toast(c, l10n.tr('err_server'));
  } catch (e) {
    debugPrint('guard: $e');
    if (c.mounted) toast(c, l10n.tr('err_unknown'));
  }
  return false;
}

// ---------- Statuts ----------

const _statusColors = {
  'pending': Colors.orange,
  'accepted': Colors.green,
  'declined': Colors.red,
  'cancelled': Colors.grey,
  'open': Colors.blue,
  'done': Colors.blueGrey,
};

Widget statusChip(BuildContext context, String s) => Chip(
      label: Text(context.tr('status_$s'), style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: _statusColors[s] ?? Colors.grey,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );

// ---------- Carte d'un trajet dans les listes ----------

class RideInfo extends StatelessWidget {
  final Ride ride;
  const RideInfo(this.ride, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = ride.driver;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Hero : le titre "vole" jusqu'à l'écran de détails
      Hero(
        tag: 'ride-title-${ride.id}',
        child: Material(
          type: MaterialType.transparency,
          child: Text(ride.route, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 4, children: [
        _iconText(Icons.calendar_today, ride.date, muted),
        _iconText(Icons.access_time, ride.time, muted),
        _iconText(Icons.payments_outlined, '${fmtPrice(ride.price)} dt', muted),
        _iconText(Icons.event_seat, context.tr('seats_left_of', {'left': ride.seatsLeft, 'total': ride.seats}), muted),
      ]),
      if (d != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.person, size: 16, color: muted),
          const SizedBox(width: 4),
          Flexible(child: Text(d.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          RatingLabel(d),
        ]),
        if (d.hasCar) _iconText(Icons.directions_car, '${d.carModel} · ${d.carPlate}', muted),
      ],
    ]);
  }
}

Widget _iconText(IconData icon, String text, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 4),
      Text(text),
    ]);

// ---------- Notes ----------

/// "★ 4.5 (3)" ou "Nouveau" si la personne n'a pas encore d'avis.
class RatingLabel extends StatelessWidget {
  final AppUser user;
  const RatingLabel(this.user, {super.key});
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (user.rating == null) {
      return Text(context.tr('new_member'), style: TextStyle(color: muted, fontSize: 12));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
      Text(' ${user.rating}', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(' (${user.ratingCount})', style: TextStyle(color: muted, fontSize: 12)),
    ]);
  }
}

/// Étoiles : affichage seul, ou sélection si [onChanged] est donné.
class Stars extends StatelessWidget {
  final int value;
  final double size;
  final ValueChanged<int>? onChanged;
  const Stars(this.value, {super.key, this.size = 18, this.onChanged});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final icon = AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              i < value ? Icons.star_rounded : Icons.star_outline_rounded,
              key: ValueKey(i < value),
              color: Colors.amber,
              size: size,
            ),
          );
          return onChanged == null
              ? icon
              : IconButton(onPressed: () => onChanged!(i + 1), icon: icon, padding: EdgeInsets.zero);
        }),
      );
}

Widget avatar(AppUser u, {double radius = 24}) => CircleAvatar(
      radius: radius,
      backgroundImage: u.photo != null ? MemoryImage(base64Decode(u.photo!)) : null,
      child: u.photo == null ? Text(u.initial) : null,
    );

// ---------- Contact ----------

/// Numéro local à 8 chiffres (Tunisie) -> format international pour WhatsApp.
String waNumber(String phone) {
  final p = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (p.startsWith('+')) return p.substring(1);
  if (p.startsWith('00')) return p.substring(2);
  if (p.length == 8) return '216$p';
  return p;
}

Future<void> openUrl(BuildContext c, Uri uri) async {
  final err = c.tr('err_open_app');
  bool ok;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && c.mounted) toast(c, err);
}

/// Boutons Appeler / WhatsApp, ou un message si la personne n'a pas mis de numéro.
class ContactButtons extends StatelessWidget {
  final AppUser user;
  final String message;
  const ContactButtons(this.user, {super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    if (!user.hasPhone) {
      return Text(context.tr('no_phone'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    final phone = user.phone.trim();
    return Wrap(spacing: 8, runSpacing: 4, children: [
      FilledButton.tonalIcon(
        onPressed: () => openUrl(context, Uri(scheme: 'tel', path: phone)),
        icon: const Icon(Icons.call),
        label: Text(context.tr('call')),
      ),
      FilledButton.tonalIcon(
        onPressed: () => openUrl(context, Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(message)}')),
        icon: const Icon(Icons.chat),
        label: const Text('WhatsApp'),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
      ),
    ]);
  }
}

// ---------- États vides / chargement / animations ----------

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // ListView pour que le "tirer pour rafraîchir" fonctionne aussi quand c'est vide
    return ListView(children: [
      const SizedBox(height: 100),
      Icon(icon, size: 64, color: muted.withValues(alpha: 0.5)),
      const SizedBox(height: 12),
      Text(text, textAlign: TextAlign.center, style: TextStyle(color: muted)),
    ]);
  }
}

/// Apparition en fondu + glissement, décalée selon la position dans la liste.
class FadeSlideIn extends StatelessWidget {
  final int index;
  final Widget child;
  const FadeSlideIn({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 350 + 60 * index.clamp(0, 8)),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
        ),
        child: child,
      );
}

/// Squelette animé (effet "shimmer") affiché pendant le chargement d'une liste.
class SkeletonList extends StatefulWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});
  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final light = Theme.of(context).colorScheme.surface;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
        );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          colors: [base, light, base],
          stops: const [0.25, 0.5, 0.75],
          begin: Alignment(-1 - 2 + 4 * _c.value, 0),
          end: Alignment(1 - 2 + 4 * _c.value, 0),
        ).createShader(rect),
        child: child,
      ),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.count,
        itemBuilder: (_, __) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bar(180, 18),
              bar(240, 12),
              bar(140, 12),
              bar(100, 12),
            ]),
          ),
        ),
      ),
    );
  }
}
