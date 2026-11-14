import 'package:campus_carpool/screens/alerts_screen.dart';
import 'package:campus_carpool/screens/search_screen.dart';
import 'package:campus_carpool/services/firestore_service.dart';
import 'package:campus_carpool/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_data.dart';
import 'helpers.dart';

/// Le design system (theme.dart) s'applique sans erreur, en clair comme en sombre.
void main() {
  setUp(() async {
    await fakeDb();
    FirestoreService.uid = 'demo';
  });

  test('thème clair et sombre : police, couleurs de la marque, fonds', () {
    final light = AppTheme.of(Brightness.light);
    final dark = AppTheme.of(Brightness.dark);
    expect(light.textTheme.bodyMedium!.fontFamily, AppTheme.font);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    // Cartes blanches sur fond gris en clair ; fond sombre en sombre
    expect(light.scaffoldBackgroundColor, isNot(light.cardTheme.color));
    expect(dark.scaffoldBackgroundColor, dark.colorScheme.surface);
  });

  for (final brightness in Brightness.values) {
    testWidgets('écrans avec le vrai thème (${brightness.name})', (tester) async {
      final theme = AppTheme.of(brightness);

      // Recherche : en-tête en dégradé, filtres, carte de trajet
      await tester.pumpWidget(testApp(const Scaffold(body: SearchScreen()), theme: theme));
      await tester.pumpAndSettle();
      expect(find.text('Où allez-vous ?'), findsOneWidget);
      expect(find.text('1 offre trouvée'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // État vide (aucune alerte)
      await tester.pumpWidget(testApp(const AlertsScreen(), theme: theme));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
