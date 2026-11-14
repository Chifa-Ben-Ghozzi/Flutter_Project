import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Design system de l'application : couleurs, police, formes et styles des composants,
/// définis une seule fois pour que tous les écrans restent cohérents (clair et sombre).
///
/// Style : fond légèrement gris, cartes blanches à ombre douce, boutons "pilule",
/// police Plus Jakarta Sans et un dégradé indigo → violet pour les zones de marque.
class AppTheme {
  /// Couleurs de la marque : indigo vif et violet, utilisées ensemble dans [brandGradient].
  static const seed = Color(0xFF4F46E5);
  static const violet = Color(0xFF7C3AED);
  static const deep = Color(0xFF312E81);

  /// Police embarquée (assets/fonts, licence SIL OFL).
  static const font = 'PlusJakartaSans';

  static const radius = 16.0;
  static const cardRadius = 22.0;

  /// Dégradé des en-têtes (recherche, profil, connexion, écran de démarrage).
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [seed, violet],
  );

  /// Fond des pages : gris très clair en mode clair, pour que les cartes blanches ressortent.
  static Color background(ColorScheme s) => s.brightness == Brightness.light ? const Color(0xFFF5F6FA) : s.surface;

  /// Fond des cartes et des barres : blanc en mode clair, une teinte au-dessus du fond en mode sombre.
  static Color card(ColorScheme s) => s.brightness == Brightness.light ? s.surfaceContainerLowest : s.surfaceContainer;

  /// Ombre douce des cartes (aucune en mode sombre, où une bordure fine la remplace).
  static List<BoxShadow> shadow(ColorScheme s) => s.brightness == Brightness.light
      ? [BoxShadow(color: const Color(0xFF1E1B4B).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))]
      : const [];

  static ThemeData of(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity, // garde l'indigo vif de la marque
    );
    final light = brightness == Brightness.light;
    final bg = background(scheme);
    final cardColor = card(scheme);
    final hairline = scheme.outlineVariant.withValues(alpha: light ? 0.5 : 0.35);

    // Typographie : Plus Jakarta Sans, titres serrés et plus gras
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: font).textTheme;
    final text = base.copyWith(
      headlineMedium: base.headlineMedium!.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: base.headlineSmall!.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: base.titleLarge!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: base.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium!.copyWith(height: 1.4),
    );
    final label = text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w700);
    final rounded = BorderRadius.circular(radius);
    // Champ "rempli" : le libellé flotte à l'intérieur du champ ; un trait coloré en bas quand il est actif
    UnderlineInputBorder border(Color color, [double width = 0]) => UnderlineInputBorder(
          borderRadius: rounded,
          borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
        );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: font,
      textTheme: text,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      // Transitions entre pages : fondu + glissement (Android), glissement natif (iOS)
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),

      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge!.copyWith(fontSize: 21, fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),

      cardTheme: CardThemeData(
        elevation: light ? 2 : 0,
        shadowColor: const Color(0xFF1E1B4B).withValues(alpha: 0.18),
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: light ? BorderSide.none : BorderSide(color: hairline),
        ),
      ),

      // Champs remplis, sans bordure au repos, bordure colorée quand ils sont actifs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: light ? const Color(0xFFF1F2F7) : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(scheme.primary, 2),
        errorBorder: border(scheme.error, 1.5),
        focusedErrorBorder: border(scheme.error, 2),
        prefixIconColor: scheme.onSurfaceVariant,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        floatingLabelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      ),

      // Boutons "pilule"
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          shape: const StadiumBorder(),
          textStyle: label,
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: label,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const CircleBorder())),

      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        backgroundColor: cardColor,
        side: BorderSide(color: hairline),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        labelStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.primary, size: 18),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: hairline),
          textStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: rounded),
        titleTextStyle: text.titleMedium!.copyWith(fontSize: 15.5, color: scheme.onSurface),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        indicatorColor: scheme.primary.withValues(alpha: light ? 0.12 : 0.28),
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 70,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium!.copyWith(
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            )),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        extendedTextStyle: label,
        shape: const StadiumBorder(),
      ),

      tabBarTheme: TabBarThemeData(
        labelStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w600),
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(100)),
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(100),
      ),

      dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),

      badgeTheme: const BadgeThemeData(backgroundColor: Color(0xFFEF4444), textColor: Colors.white),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: light ? const Color(0xFF1E1B4B) : scheme.inverseSurface,
        contentTextStyle: text.bodyMedium!
            .copyWith(color: light ? Colors.white : scheme.onInverseSurface, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: text.titleLarge!.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}
