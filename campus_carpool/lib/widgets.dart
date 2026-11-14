import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'l10n.dart';
import 'models.dart';
import 'services/exceptions.dart';
import 'theme.dart';

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String fmtPrice(double p) => p == p.roundToDouble() ? p.toInt().toString() : p.toStringAsFixed(1);

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

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

// ---------- Dates lisibles ----------

/// "Aujourd'hui", "Demain", sinon "ven. 14 nov." (dans la langue choisie).
String friendlyDate(BuildContext context, DateTime d) {
  final today = DateUtils.dateOnly(DateTime.now());
  final diff = DateUtils.dateOnly(d).difference(today).inDays;
  if (diff == 0) return context.tr('today');
  if (diff == 1) return context.tr('tomorrow');
  final days = context.tr('weekdays').split('|');
  final months = context.tr('months').split('|');
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

// ---------- Statuts ----------

/// Couleur de chaque statut ; affichée en version douce (fond pâle, texte coloré).
Color statusColor(BuildContext context, String s) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (s) {
    'pending' => dark ? Colors.orange.shade300 : Colors.orange.shade800,
    'accepted' => dark ? Colors.green.shade300 : Colors.green.shade700,
    'declined' => dark ? Colors.red.shade300 : Colors.red.shade700,
    'open' => Theme.of(context).colorScheme.primary,
    'done' => dark ? Colors.teal.shade200 : Colors.teal.shade700,
    _ => Theme.of(context).colorScheme.onSurfaceVariant, // cancelled
  };
}

/// Pastille de statut : point coloré + libellé, sur un fond pâle de la même couleur.
Widget statusChip(BuildContext context, String s) {
  final c = statusColor(context, s);
  return Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(context.tr('status_$s'), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ---------- Marque ----------

/// Logo de l'app : carré arrondi au dégradé de la marque, avec une voiture.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(size * 0.32),
          boxShadow: [
            BoxShadow(color: AppTheme.seed.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: size * 0.58),
      );
}

/// Bloc au dégradé de la marque, aux coins très arrondis (en-têtes de la recherche et du profil).
class GradientPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GradientPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: AppTheme.seed.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(children: [
          // Cercles décoratifs translucides
          Positioned(right: -40, top: -50, child: _bubble(160, 0.10)),
          Positioned(right: 60, bottom: -70, child: _bubble(120, 0.07)),
          Padding(padding: padding, child: child),
        ]),
      );

  static Widget _bubble(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
      );
}

/// Onglets dans un rail arrondi : l'onglet actif est une pilule de la couleur de la marque.
class SegmentedTabBar extends StatelessWidget {
  final List<Widget> tabs;
  const SegmentedTabBar({super.key, required this.tabs});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.card(scheme),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: TabBar(
        tabs: tabs,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(100)),
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(100),
      ),
    );
  }
}

/// Titre de section (en gras), avec une action facultative à droite.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 10)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

// ---------- Trajet : itinéraire, prix, carte ----------

/// Itinéraire dessiné comme une ligne de temps : ○ départ, │, ● arrivée.
class RouteTimeline extends StatelessWidget {
  final String from;
  final String to;
  final double fontSize;
  const RouteTimeline(this.from, this.to, {super.key, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: fontSize, height: 1.3, fontWeight: FontWeight.w600, color: scheme.onSurface);
    final line = fontSize * 1.3; // hauteur d'une ligne de texte
    const dot = 10.0;
    final gap = line * 0.7;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.only(top: (line - dot) / 2),
        child: Column(children: [
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.primary, width: 2.5)),
          ),
          Container(width: 2, height: line + gap - dot, color: scheme.outlineVariant),
          Container(width: dot, height: dot, decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary)),
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(from, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: gap),
          Text(to, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
  }
}

/// Prix mis en avant ("4 dt").
class PricePill extends StatelessWidget {
  final double price;
  final bool large;
  const PricePill(this.price, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 11, vertical: large ? 8 : 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: fmtPrice(price),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: large ? 22 : 17, letterSpacing: -0.3),
          ),
          TextSpan(text: ' dt', style: TextStyle(fontWeight: FontWeight.w700, fontSize: large ? 14 : 12)),
        ]),
        style: TextStyle(color: color),
      ),
    );
  }
}

/// Carte d'un trajet dans les listes : heure et date à gauche, itinéraire au centre, prix à droite ;
/// en bas le conducteur (ou les places) et un statut ; [footer] pour les actions propres à l'écran.
class RideCard extends StatelessWidget {
  final Ride ride;
  final VoidCallback? onTap;
  final bool showDriver;
  final String? status;
  final Widget? footer;

  const RideCard(this.ride, {super.key, this.onTap, this.showDriver = true, this.status, this.footer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final d = ride.driver;
    final full = ride.seatsLeft == 0;
    final seats = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: (full ? scheme.error : scheme.onSurfaceVariant).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.event_seat_rounded, size: 14, color: full ? scheme.error : muted),
        const SizedBox(width: 4),
        Text(
          context.tr('seats_left_of', {'left': ride.seatsLeft, 'total': ride.seats}),
          style: TextStyle(color: full ? scheme.error : muted, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]),
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Heure, date (et "régulier") à gauche ; prix à droite
            Row(children: [
              Text(ride.time, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(friendlyDate(context, ride.dateTime),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (ride.isRecurring) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: context.tr('recurring_ride'),
                  child: Icon(Icons.repeat_rounded, size: 16, color: scheme.primary),
                ),
              ],
              const Spacer(),
              PricePill(ride.price),
            ]),
            const SizedBox(height: 14),
            // Hero : l'itinéraire "vole" jusqu'à l'écran de détails
            Hero(
              tag: 'ride-title-${ride.id}',
              child: Material(type: MaterialType.transparency, child: RouteTimeline(ride.from, ride.to, fontSize: 16)),
            ),
            const SizedBox(height: 14),
            // Pied de carte sur fond teinté : conducteur (ou places) et statut
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                if (showDriver && d != null) ...[
                  avatar(d, radius: 15),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      RatingLabel(d, compact: true),
                    ]),
                  ),
                ] else
                  seats,
                const Spacer(),
                const SizedBox(width: 6),
                if (status != null) statusChip(context, status!) else if (showDriver) seats,
              ]),
            ),
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ]),
        ),
      ),
    );
  }
}

/// Une ligne d'information avec icône (dans les cartes de détail).
class InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const InfoLine(this.icon, this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Row(children: [
      Icon(icon, size: 18, color: c),
      const SizedBox(width: 8),
      Flexible(child: Text(text, style: TextStyle(color: color, fontWeight: color == null ? null : FontWeight.w600))),
    ]);
  }
}

/// Un passager d'un trajet : avatar, nom, note ; boutons Accepter / Refuser quand la demande est en attente.
class PassengerRequest extends StatelessWidget {
  final AppUser user;
  final String status;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onTap;
  final Widget? below;

  const PassengerRequest(this.user, this.status, {super.key, this.onAccept, this.onDecline, this.onTap, this.below});

  @override
  Widget build(BuildContext context) {
    final red = statusColor(context, 'declined');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Row(children: [
            avatar(user, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                RatingLabel(user),
              ]),
            ),
            if (onAccept == null) statusChip(context, status),
          ]),
        ),
        if (onAccept != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: red, minimumSize: const Size(0, 40)),
                onPressed: onDecline,
                icon: const Icon(Icons.close, size: 18),
                label: Text(context.tr('decline')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: onAccept,
                icon: const Icon(Icons.check, size: 18),
                label: Text(context.tr('accept')),
              ),
            ),
          ]),
        ],
        if (below != null) Padding(padding: const EdgeInsets.only(top: 8), child: below),
      ]),
    );
  }
}

/// Carte de section avec un titre (écran de détails, profil…).
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Color? color;
  const SectionCard({super.key, this.title, required this.child, this.color});

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              Text(
                title!,
                style: TextStyle(
                  fontSize: 15,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ]),
        ),
      );
}

// ---------- Notes ----------

/// "★ 4.5 (3)" ou "Nouveau" si la personne n'a pas encore d'avis.
class RatingLabel extends StatelessWidget {
  final AppUser user;

  /// Version plus petite (pied des cartes de trajet).
  final bool compact;
  const RatingLabel(this.user, {super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final small = compact ? 11.5 : 12.0;
    if (user.rating == null) {
      return Text(context.tr('new_member'), style: TextStyle(color: muted, fontSize: small));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, color: const Color(0xFFF59E0B), size: compact ? 15 : 18),
      Text(' ${user.rating}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 12.5 : null)),
      Text(' (${user.ratingCount})', style: TextStyle(color: muted, fontSize: small)),
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

/// Couleurs des avatars sans photo : chaque personne garde toujours la même (calculée depuis son id).
const _avatarColors = [
  Color(0xFF4F46E5),
  Color(0xFF7C3AED),
  Color(0xFF0EA5E9),
  Color(0xFF14B8A6),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFF97316),
  Color(0xFFEC4899),
];

Color avatarColor(AppUser u) {
  final key = u.id.isNotEmpty ? u.id : u.name;
  final hash = key.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
  return _avatarColors[hash % _avatarColors.length];
}

/// Photo de profil, ou l'initiale sur un dégradé de couleur propre à la personne.
Widget avatar(AppUser u, {double radius = 24}) {
  if (u.photo != null) {
    return CircleAvatar(radius: radius, backgroundImage: MemoryImage(base64Decode(u.photo!)));
  }
  final c = avatarColor(u);
  return Container(
    width: radius * 2,
    height: radius * 2,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(c, Colors.white, 0.18)!, c],
      ),
    ),
    child: Text(
      u.initial,
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.85, height: 1),
    ),
  );
}

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
/// [extra] (ex: bouton de la messagerie de l'app) est placé en premier.
class ContactButtons extends StatelessWidget {
  final AppUser user;
  final String message;
  final Widget? extra;
  const ContactButtons(this.user, {super.key, required this.message, this.extra});
  @override
  Widget build(BuildContext context) {
    if (!user.hasPhone) {
      final text =
          Text(context.tr('no_phone'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
      if (extra == null) return text;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [extra!, const SizedBox(height: 8), text]);
    }
    final phone = user.phone.trim();
    return Wrap(spacing: 8, runSpacing: 4, children: [
      if (extra != null) extra!,
      FilledButton.tonalIcon(
        onPressed: () => openUrl(context, Uri(scheme: 'tel', path: phone)),
        icon: const Icon(Icons.call),
        label: Text(context.tr('call')),
      ),
      FilledButton.tonalIcon(
        onPressed: () =>
            openUrl(context, Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(message)}')),
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
    final scheme = Theme.of(context).colorScheme;
    // ListView pour que le "tirer pour rafraîchir" fonctionne aussi quand c'est vide
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 32), children: [
      const SizedBox(height: 80),
      Center(
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary.withValues(alpha: 0.16), AppTheme.violet.withValues(alpha: 0.06)],
            ),
          ),
          child: Icon(icon, size: 50, color: scheme.primary),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
      ),
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
