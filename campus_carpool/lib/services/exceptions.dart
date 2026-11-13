/// Erreur métier (message en français, traduit à l'affichage par L10n.trServer).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Serveur injoignable (pas de réseau).
class NetworkException implements Exception {}
