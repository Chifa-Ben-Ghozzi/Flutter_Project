import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../validators.dart';
import '../widgets.dart';
import 'ride_details_screen.dart';

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
      final s = ProfileStats.compute(await Api.myRides(), await Api.myBookings());
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
    final ok = await guard(context, () => auth.updateProfile({
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: Stack(children: [
            GestureDetector(onTap: pickPhoto, child: avatar(user, radius: 50)),
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.camera_alt, size: 16, color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Center(child: Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        Center(child: Text(user.email ?? '', style: TextStyle(color: muted))),
        Center(
          child: TextButton(
            onPressed: () => showUserProfile(context, user.id),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              RatingLabel(user),
              Text('  · ${context.tr('see_my_reviews')}'),
            ]),
          ),
        ),
        if (stats != null) ...[
          const SizedBox(height: 8),
          statsGrid(user, stats!),
        ],
        const SizedBox(height: 20),
        sectionTitle('my_info'),
        TextFormField(
          controller: name,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: context.tr('name'), prefixIcon: const Icon(Icons.person), border: const OutlineInputBorder()),
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
            border: const OutlineInputBorder(),
          ),
          validator: (v) => t(Validators.phone(v)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: model,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: context.tr('car_model'), prefixIcon: const Icon(Icons.directions_car), border: const OutlineInputBorder()),
          onChanged: (_) => formKey.currentState?.validate(), // re-vérifie la plaque
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: plate,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: context.tr('plate'), prefixIcon: const Icon(Icons.pin), border: const OutlineInputBorder()),
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
        const SizedBox(height: 24),
        sectionTitle('settings'),
        settingsCard(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.read<AuthProvider>().logout(),
          icon: const Icon(Icons.logout),
          label: Text(context.tr('logout')),
        ),
      ]),
    );
  }

  Widget sectionTitle(String key) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(context.tr(key), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  /// GridView : 3 colonnes de statistiques, dans la liste qui défile.
  Widget statsGrid(AppUser user, ProfileStats s) {
    final items = [
      (Icons.directions_car, '${s.ridesAsDriver}', 'stat_driver', Colors.indigo),
      (Icons.event_seat, '${s.ridesAsPassenger}', 'stat_passenger', Colors.teal),
      (Icons.groups, '${s.seatsShared}', 'stat_seats', Colors.orange),
      (Icons.schedule, '${s.upcoming}', 'stat_upcoming', Colors.purple),
      (Icons.star_rounded, user.rating?.toString() ?? '–', 'stat_rating', Colors.amber),
      (Icons.reviews, '${user.ratingCount}', 'stat_reviews', Colors.pink),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, i) {
        final (icon, value, label, color) = items[i];
        return FadeSlideIn(
          index: i,
          child: Container(
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(context.tr(label), textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11)),
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.dark_mode_outlined),
            const SizedBox(width: 12),
            Text(context.tr('theme')),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(context.tr('theme_light'))),
                ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(context.tr('theme_dark'))),
                ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.phone_android), label: Text(context.tr('theme_system'))),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
              showSelectedIcon: false,
            ),
          ),
          const Divider(height: 24),
          Row(children: [
            const Icon(Icons.language),
            const SizedBox(width: 12),
            Expanded(child: Text(context.tr('language'))),
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
