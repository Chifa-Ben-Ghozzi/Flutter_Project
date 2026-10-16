import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current language ('fr' or 'en') and saves it on the phone.
/// It is a normal object (no static): ONE instance is created in main()
/// and given to the whole app through [L10nScope].
class L10n extends ChangeNotifier {
  String _lang = 'fr';
  String get lang => _lang;

  /// Call once in main() before runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('lang');
    if (saved == 'fr' || saved == 'en') {
      _lang = saved!;
    } else {
      // first launch: follow the phone language (English if English, else French)
      final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      _lang = code == 'en' ? 'en' : 'fr';
    }
    notifyListeners();
  }

  Future<void> setLang(String code) async {
    if (code == _lang) return;
    _lang = code;
    notifyListeners(); // every widget that uses this object redraws
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', code);
  }

  /// Translate a key.
  String tr(String key) => _strings[_lang]?[key] ?? _strings['fr']![key] ?? key;

  /// The backend sends its error messages in French.
  /// This translates the ones we know about when the app is in English.
  String trServer(String msg) => _lang == 'fr' ? msg : (_serverEn[msg] ?? msg);
}

/// Gives the [L10n] object to every widget below it.
/// Widgets that read it are rebuilt automatically when the language changes.
class L10nScope extends InheritedNotifier<L10n> {
  const L10nScope({super.key, required L10n l10n, required super.child}) : super(notifier: l10n);

  /// Use inside build(): the widget rebuilds when the language changes.
  static L10n of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L10nScope>()!.notifier!;

  /// Use inside callbacks / after an await: just reads, no rebuild.
  static L10n read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<L10nScope>()!.notifier!;
}

/// Shortcuts:  context.tr('login')   and   context.l10n.lang
extension L10nContext on BuildContext {
  L10n get l10n => L10nScope.of(this);
  String tr(String key) => L10nScope.of(this).tr(key);
}

const _serverEn = {
  'Email ou mot de passe incorrect': 'Incorrect email or password',
  'Email déjà utilisé': 'Email already in use',
  'Champs manquants': 'Missing fields',
  'Utilisez votre email universitaire': 'Use your university email',
  'Mot de passe : 6 caractères minimum': 'Password: at least 6 characters',
  'Non authentifié': 'Not signed in',
  'Trajet introuvable': 'Ride not found',
  'Trajet indisponible': 'Ride unavailable',
  'Plus de places': 'No seats left',
  'Vous ne pouvez pas réserver votre propre trajet': "You can't book your own ride",
  'Vous avez déjà une demande pour ce trajet': 'You already requested this ride',
  'Ce trajet est déjà passé': 'This ride has already left',
  'Date/heure invalide': 'Invalid date/time',
  'Places/prix invalides': 'Invalid seats/price',
  'Réservation introuvable': 'Booking not found',
  'Demande déjà traitée': 'Request already handled',
  'Plus de places disponibles': 'No seats available',
};

// ============ ADD NEW TEXTS HERE (one key, two languages) ============
const _strings = <String, Map<String, String>>{
  'fr': {
    'tagline': 'Partagez la route, partagez le trajet',
    'welcome_back': 'Bon retour 👋',
    'create_account': 'Créer un compte',
    'full_name': 'Nom complet',
    'uni_email': 'Email universitaire',
    'password': 'Mot de passe',
    'login': 'Se connecter',
    'signup': "S'inscrire",
    'have_account': 'Déjà un compte ? Connexion',
    'no_account': 'Pas de compte ? Inscription',
    'err_name': 'Entrez votre nom complet',
    'err_email_empty': 'Entrez votre email',
    'err_email_format': "Format d'email invalide",
    'err_email_uni': 'Utilisez votre email universitaire',
    'err_pwd_empty': 'Entrez votre mot de passe',
    'err_pwd_short': 'Mot de passe : 6 caractères minimum',
    'err_server': 'Serveur indisponible. Vérifiez votre connexion.',
    'confirm_password': 'Confirmer le mot de passe',
    'err_pwd_match': 'Les mots de passe ne correspondent pas',
    'pwd_match_ok': 'Les mots de passe correspondent',
    'pwd_weak': 'Faible',
    'pwd_medium': 'Moyen',
    'pwd_strong': 'Fort',
  },
  'en': {
    'tagline': 'Share the road, share the ride',
    'welcome_back': 'Welcome back 👋',
    'create_account': 'Create an account',
    'full_name': 'Full name',
    'uni_email': 'University email',
    'password': 'Password',
    'login': 'Log in',
    'signup': 'Sign up',
    'have_account': 'Already have an account? Log in',
    'no_account': "No account? Sign up",
    'err_name': 'Enter your full name',
    'err_email_empty': 'Enter your email',
    'err_email_format': 'Invalid email format',
    'err_email_uni': 'Use your university email',
    'err_pwd_empty': 'Enter your password',
    'err_pwd_short': 'Password: at least 6 characters',
    'err_server': 'Server unavailable. Check your connection.',
    'confirm_password': 'Confirm password',
    'err_pwd_match': 'Passwords do not match',
    'pwd_match_ok': 'Passwords match',
    'pwd_weak': 'Weak',
    'pwd_medium': 'Medium',
    'pwd_strong': 'Strong',
  },
};

/// Small FR | EN pill. Drop it anywhere (auth screen, profile, settings...).
/// Set [onDark] to true when it sits on the indigo gradient.
class LangSwitcher extends StatelessWidget {
  final bool onDark;
  const LangSwitcher({super.key, this.onDark = true});

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : const Color(0xFF3F51B5);
    final current = context.l10n.lang;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg(context, 'FR', 'fr', current, fg),
        _seg(context, 'EN', 'en', current, fg),
      ]),
    );
  }

  Widget _seg(BuildContext context, String label, String code, String current, Color fg) {
    final sel = current == code;
    return GestureDetector(
      onTap: () => L10nScope.read(context).setLang(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? fg : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: sel ? (onDark ? const Color(0xFF3F51B5) : Colors.white) : fg,
          ),
        ),
      ),
    );
  }
}