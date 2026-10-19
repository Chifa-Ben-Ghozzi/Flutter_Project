import 'dart:io';

import 'package:campus_carpool/l10n.dart';
import 'package:campus_carpool/models.dart';
import 'package:campus_carpool/providers/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fr = strings['fr']!;
  final en = strings['en']!;

  test('chaque texte existe en français ET en anglais', () {
    expect(fr.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'manquant en anglais');
    expect(en.keys.toSet().difference(fr.keys.toSet()), isEmpty, reason: 'manquant en français');
  });

  test('les {paramètres} sont les mêmes dans les deux langues', () {
    final param = RegExp(r'\{(\w+)\}');
    for (final k in fr.keys) {
      final a = param.allMatches(fr[k]!).map((m) => m[1]).toSet();
      final b = param.allMatches(en[k]!).map((m) => m[1]).toSet();
      expect(a, b, reason: 'clé "$k"');
    }
  });

  test("chaque context.tr('...') du code a une traduction", () {
    final used = <String>{};
    final literal = RegExp(r"""tr\('([a-z0-9_]+)'""");
    final validatorKey = RegExp(r"""'(v_[a-z0-9_]+)'""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      used.addAll(literal.allMatches(src).map((m) => m[1]!));
      used.addAll(validatorKey.allMatches(src).map((m) => m[1]!));
    }
    // Clés construites dynamiquement
    used.addAll(['pending', 'accepted', 'declined', 'cancelled', 'open', 'done'].map((s) => 'status_$s'));
    used.addAll([for (var i = 1; i <= 5; i++) 'stars_$i']);
    for (final t in ['booking_new', 'booking_accepted', 'booking_declined', 'booking_cancelled', 'ride_cancelled', 'review']) {
      used.addAll(['notif_${t}_title', 'notif_${t}_body']);
    }
    final missing = used.where((k) => !fr.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'clés sans traduction');
  });

  test('paramètres remplacés et repli sur la clé inconnue', () {
    final l = L10n('en');
    expect(l.tr('rate_name', {'name': 'Sami'}), 'Rate Sami');
    expect(l.tr('cle_inconnue'), 'cle_inconnue');
    expect(L10n('fr').tr('rate_name', {'name': 'Sami'}), 'Noter Sami');
  });

  test('messages du serveur traduits en anglais', () {
    expect(L10n('en').trServer('Plus de places'), 'No seats left');
    expect(L10n('fr').trServer('Plus de places'), 'Plus de places');
    expect(L10n('en').trServer('message inconnu'), 'message inconnu');
  });

  test('notification réécrite dans la langue choisie', () {
    const n = AppNotification(
      id: 'n1',
      type: 'booking_accepted',
      title: 'Réservation acceptée ✅',
      body: 'texte serveur',
      data: {'name': 'Amira', 'from': 'Ariana', 'to': 'Esprit', 'date': '2026-01-05', 'time': '08:00'},
    );
    expect(notifTitle(n, L10n('en')), 'Booking accepted ✅');
    expect(notifBody(n, L10n('en')), 'Amira accepted your request for Ariana → Esprit (2026-01-05 08:00).');
    // Anciennes notifications sans données : texte du serveur
    const old = AppNotification(id: 'n2', type: 'booking_new', body: 'texte serveur');
    expect(notifBody(old, L10n('en')), 'texte serveur');
  });
}
