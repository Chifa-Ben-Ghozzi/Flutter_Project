/// Guide hors ligne : réponses par mots-clés, utilisées quand l'assistant IA est injoignable.
class OfflineGuide {
  static bool _hasAny(String text, List<String> terms) => terms.any(text.contains);

  /// Clé de traduction de la réponse à [question].
  static String answerKey(String question) {
    final text = question.toLowerCase();
    if (_hasAny(text, ['cancel', 'delete', 'annul', 'supprim'])) return 'chat_a_cancel';
    if (_hasAny(text, ['no rides', 'nothing', 'empty', 'no results', 'not found', 'aucun', 'rien', 'vide'])) {
      return 'chat_a_empty';
    }
    if (_hasAny(text, ['offer', 'post', 'publish', 'create a ride', 'driver', 'publier', 'proposer', 'conducteur'])) {
      return 'chat_a_offer';
    }
    if (_hasAny(text, ['accept', 'decline', 'approve', 'passenger', 'request status', 'accepter', 'refuser', 'passager'])) {
      return 'chat_a_accept';
    }
    if (_hasAny(text, ['book', 'booking', 'reserve', 'reservation', 'request', 'seat', 'place', 'réserv', 'demande'])) {
      return 'chat_a_booking';
    }
    if (_hasAny(text, [
      'login', 'log in', 'sign in', 'register', 'account', 'email', 'password', //
      'inscri', 'connect', 'compte', 'mot de passe',
    ])) {
      return 'chat_a_account';
    }
    if (_hasAny(text, [
      'profile', 'photo', 'phone', 'car', 'vehicle', 'profil', 'picture', 'log out', 'logout', 'sign out', //
      'voiture', 'téléphone', 'déconnex',
    ])) {
      return 'chat_a_profile';
    }
    if (_hasAny(
        text, ['find', 'search', 'look for', 'destination', 'filter', 'ride', 'trajet', 'chercher', 'trouver', 'recherche'])) {
      return 'chat_a_search';
    }
    if (_hasAny(text, ['hello', 'hi', 'hey', 'help', 'what can you do', 'bonjour', 'salut', 'aide'])) {
      return 'chat_a_hello';
    }
    return 'chat_a_default';
  }

  /// Onglet à proposer pour [question] (0 Chercher … 4 Profil), ou null.
  static int? destinationFor(String question) {
    final text = question.toLowerCase();
    if (_hasAny(text, ['cancel', 'delete', 'annul'])) {
      return _hasAny(text, ['booking', 'reservation', 'seat', 'place']) ? 3 : 2;
    }
    if (_hasAny(text, ['offer', 'post', 'publish', 'create a ride', 'publier', 'proposer'])) return 1;
    if (_hasAny(text, ['accept', 'decline', 'approve', 'passenger', 'refuser', 'passager'])) return 2;
    if (_hasAny(text, ['book', 'booking', 'reserve', 'reservation', 'seat', 'place', 'réserv'])) return 3;
    if (_hasAny(text, ['profile', 'photo', 'phone', 'car', 'vehicle', 'profil', 'picture', 'log out', 'logout', 'sign out'])) {
      return 4;
    }
    if (_hasAny(text, ['find', 'search', 'destination', 'filter', 'ride', 'trajet', 'chercher', 'trouver'])) return 0;
    return null;
  }
}
