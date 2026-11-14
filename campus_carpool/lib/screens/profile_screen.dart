import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../l10n.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../routes.dart';
import '../theme.dart';
import '../validators.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';
import '../repositories/booking_repository.dart';
import '../repositories/ride_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name, phone, model, plate;
  ProfileStats? stats;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    // Valeurs de départ du formulaire = profil actuel (context.read est permis dans initState)
    final u = context.read<AuthProvider>().user;
    name = TextEditingController(text: u?.name ?? '');
    phone = TextEditingController(text: u?.phone ?? '');
    model = TextEditingController(text: u?.carModel ?? '');
    plate = TextEditingController(text: u?.carPlate ?? '');
    loadStats();
  }

  @override
  void dispose() {
    for (final c in [name, phone, model, plate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> loadStats() async {
    try {
      final s = ProfileStats.compute(await RideRepository.myRides(), await BookingRepository.myBookings());
      if (mounted) setState(() => stats = s);
    } catch (_) {
      // Pas de statistiques si le serveur est injoignable
    }
  }

  String? t(String? key) => key == null ? null : context.tr(key);

  Future<void> pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 300, imageQuality: 60);
    if (x == null || !mounted) return;
    final b64 = base64Encode(await x.readAsBytes());
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    await guard(context, () => auth.updateProfile({'photo': b64}));
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final done = context.tr('toast_profile_saved');
    setState(() => saving = true);
    final ok = await guard(
        context,
        () => auth.updateProfile({
              'name': name.text.trim(),
              'phone': phone.text.replaceAll(' ', ''),
              'car': {'model': model.text.trim(), 'plate': plate.text.trim()},
            }));
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) toast(context, done);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        header(user),
        if (stats != null) ...[
          const SizedBox(height: 16),
          statsGrid(user, stats!),
        ],
        const SizedBox(height: 24),
        sectionTitle('my_info'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: context.tr('name'), prefixIcon: const Icon(Icons.person)),
                validator: (v) => t(Validators.name(v)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.tr('phone'),
                  helperText: context.tr('phone_helper'),
                  prefixIcon: const Icon(Icons.phone),
                ),
                validator: (v) => t(Validators.phone(v)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: model,
                textInputAction: TextInputAction.next,
                decoration:
                    InputDecoration(labelText: context.tr('car_model'), prefixIcon: const Icon(Icons.directions_car)),
                onChanged: (_) => formKey.currentState?.validate(), // re-vérifie la plaque
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: plate,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: context.tr('plate'), prefixIcon: const Icon(Icons.pin)),
                validator: (v) => t(Validators.plate(v, model.text)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(context.tr('save')),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        // Alertes de trajet : prévenu dès qu'un trajet correspondant est publié
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: iconBubble(Icons.notifications_active_rounded, const Color(0xFF7C3AED)),
            title: Text(context.tr('alerts'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(context.tr('alerts_subtitle')),
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
            onTap: () => Navigator.pushNamed(context, AppRoutes.alerts),
          ),
        ),
        const SizedBox(height: 24),
        sectionTitle('settings'),
        settingsCard(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: statusColor(context, 'declined'),
            backgroundColor: statusColor(context, 'declined').withValues(alpha: 0.08),
            side: BorderSide.none,
          ),
          onPressed: () => context.read<AuthProvider>().logout(),
          icon: const Icon(Icons.logout),
          label: Text(context.tr('logout')),
        ),
      ]),
    );
  }

  Widget sectionTitle(String key) => SectionHeader(context.tr(key));

  /// Icône dans une pastille colorée (lignes de réglages).
  Widget iconBubble(IconData icon, Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 21),
      );

  /// En-tête au dégradé : photo (touchez pour la changer), nom, e-mail et note.
  Widget header(AppUser user) {
    return GradientPanel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(children: [
        Stack(children: [
          GestureDetector(
            onTap: pickPhoto,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.9)),
              child: avatar(user, radius: 44),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)],
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 17, color: AppTheme.seed),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(user.name,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        const SizedBox(height: 2),
        Text(user.email ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
        const SizedBox(height: 14),
        // Note + lien vers mes avis, dans une pilule blanche
        Material(
          color: Colors.white,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showUserProfile(context, user.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Color(0xFF1E1B4B)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Theme(
                    data: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.seed)),
                    child: RatingLabel(user),
                  ),
                  Text('  ·  ${context.tr('see_my_reviews')}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.seed)),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.seed),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// GridView : 3 colonnes de statistiques, dans la liste qui défile.
  Widget statsGrid(AppUser user, ProfileStats s) {
    final items = [
      (Icons.directions_car_filled_rounded, '${s.ridesAsDriver}', 'stat_driver', const Color(0xFF4F46E5)),
      (Icons.event_seat_rounded, '${s.ridesAsPassenger}', 'stat_passenger', const Color(0xFF14B8A6)),
      (Icons.groups_rounded, '${s.seatsShared}', 'stat_seats', const Color(0xFFF97316)),
      (Icons.schedule_rounded, '${s.upcoming}', 'stat_upcoming', const Color(0xFF7C3AED)),
      (Icons.star_rounded, user.rating?.toString() ?? '–', 'stat_rating', const Color(0xFFF59E0B)),
      (Icons.reviews_rounded, '${user.ratingCount}', 'stat_reviews', const Color(0xFFEC4899)),
    ];
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (_, i) {
        final (icon, value, label, color) = items[i];
        return FadeSlideIn(
          index: i,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.card(scheme),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.shadow(scheme),
              border: scheme.brightness == Brightness.dark
                  ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35))
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 32,
                height: 32,
                decoration:
                    BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              // Hauteur fixe de 2 lignes : les chiffres restent alignés d'une tuile à l'autre
              SizedBox(
                height: 30,
                child: Text(context.tr(label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, height: 1.3, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget settingsCard() {
    final settings = context.watch<SettingsProvider>();
    final l10n = context.watch<L10n>();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            iconBubble(Icons.dark_mode_rounded, const Color(0xFF4F46E5)),
            const SizedBox(width: 12),
            Text(context.tr('theme'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                    value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(context.tr('theme_light'))),
                ButtonSegment(
                    value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(context.tr('theme_dark'))),
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.phone_android),
                    label: Text(context.tr('theme_system'))),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
              showSelectedIcon: false,
            ),
          ),
          const Divider(height: 24),
          Row(children: [
            iconBubble(Icons.translate_rounded, const Color(0xFF14B8A6)),
            const SizedBox(width: 12),
            Expanded(child: Text(context.tr('language'), style: const TextStyle(fontWeight: FontWeight.w700))),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fr', label: Text('FR')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {l10n.lang},
              onSelectionChanged: (s) => l10n.setLang(s.first),
              showSelectedIcon: false,
            ),
          ]),
        ]),
      ),
    );
  }
}
