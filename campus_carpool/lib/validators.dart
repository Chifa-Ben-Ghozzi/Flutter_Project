/// Validators des formulaires (Form + TextFormField).
/// Chaque fonction renvoie null si la valeur est valide, sinon une CLÉ de traduction
/// (ex: 'v_required') que l'écran traduit avec context.tr(). Faciles à tester (voir test/).
class Validators {
  static String? place(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'v_required';
    if (s.length < 2) return 'v_min2';
    return null;
  }

  /// La destination doit être remplie et différente du départ.
  static String? destination(String? v, String from) =>
      place(v) ?? (v!.trim().toLowerCase() == from.trim().toLowerCase() ? 'v_same_place' : null);

  /// Date + heure du trajet : obligatoires et dans le futur.
  static String? dateTime(DateTime? date, int? hour, int? minute, {DateTime? now}) {
    if (date == null) return 'v_pick_date';
    if (hour == null || minute == null) return 'v_pick_time';
    final dt = DateTime(date.year, date.month, date.day, hour, minute);
    if (dt.isBefore(now ?? DateTime.now())) return 'v_time_past';
    return null;
  }

  static String? seats(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'v_integer';
    if (n < 1 || n > 8) return 'v_seats_range';
    return null;
  }

  static double? parsePrice(String? v) => double.tryParse((v ?? '').trim().replaceAll(',', '.'));

  static String? price(String? v) {
    final p = parsePrice(v);
    if (p == null) return 'v_number';
    if (p < 0) return 'v_positive';
    if (p > 200) return 'v_price_high';
    return null;
  }

  static String? name(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'v_name_required';
    if (s.length < 2) return 'v_min2';
    return null;
  }

  /// Facultatif ; s'il est rempli : 8 chiffres (Tunisie) ou format international +XXX…
  static String? phone(String? v) {
    final s = (v ?? '').replaceAll(' ', '');
    if (s.isEmpty) return null;
    return RegExp(r'^(\+\d{8,15}|\d{8})$').hasMatch(s) ? null : 'v_phone';
  }

  /// Si une voiture est indiquée, la plaque devient obligatoire (et inversement).
  static String? plate(String? v, String model) {
    final hasModel = model.trim().isNotEmpty;
    final p = (v ?? '').trim();
    if (hasModel && p.isEmpty) return 'v_plate_required';
    if (!hasModel && p.isNotEmpty) return 'v_model_required';
    if (p.isNotEmpty && p.length < 4) return 'v_plate_short';
    return null;
  }
}
