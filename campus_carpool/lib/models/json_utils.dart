/// Petites fonctions de conversion JSON partagées par les modèles.
library;

double? toDoubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();

List<T> listOf<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? []).map((e) => f(Map<String, dynamic>.from(e))).toList();

Map<String, dynamic> asJson(dynamic v) => Map<String, dynamic>.from(v);
