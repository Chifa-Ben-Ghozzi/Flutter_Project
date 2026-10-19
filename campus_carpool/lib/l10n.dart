import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Langue de l'application ('fr' ou 'en'), enregistrée sur le téléphone.
/// Une seule instance, créée dans main() et donnée à toute l'app par [L10nScope]
/// (et par Provider, pour `context.read<L10n>()`).
class L10n extends ChangeNotifier {
  static const supported = ['fr', 'en'];

  String _lang = 'fr';
  String get lang => _lang;

  L10n([String? lang]) {
    if (lang != null) _lang = lang;
  }

  /// À appeler une fois dans main() avant runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('lang');
    if (supported.contains(saved)) {
      _lang = saved!;
    } else {
      // Premier lancement : suit la langue du téléphone (anglais si anglais, sinon français)
      final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      _lang = code == 'en' ? 'en' : 'fr';
    }
    notifyListeners();
  }

  Future<void> setLang(String code) async {
    if (code == _lang || !supported.contains(code)) return;
    _lang = code;
    notifyListeners(); // tous les widgets qui utilisent les textes sont redessinés
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', code);
  }

  /// Traduit une clé. Les {paramètres} sont remplacés : tr('rate_name', {'name': 'Sami'}).
  String tr(String key, [Map<String, Object?> args = const {}]) {
    var s = strings[_lang]?[key] ?? strings['fr']![key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
    return s;
  }

  /// Le backend renvoie ses messages d'erreur en français : on traduit ceux qu'on connaît.
  String trServer(String msg) => _lang == 'fr' ? msg : (_serverEn[msg] ?? msg);
}

/// Donne l'objet [L10n] à tous les widgets en dessous.
/// Les widgets qui l'utilisent sont redessinés automatiquement au changement de langue.
class L10nScope extends InheritedNotifier<L10n> {
  const L10nScope({super.key, required L10n l10n, required super.child}) : super(notifier: l10n);

  static L10n of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<L10nScope>()!.notifier!;
}

/// Raccourcis :  context.tr('login')   context.tr('rate_name', {'name': n})   context.l10n.lang
extension L10nContext on BuildContext {
  L10n get l10n => L10nScope.of(this);
  String tr(String key, [Map<String, Object?> args = const {}]) => L10nScope.of(this).tr(key, args);
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
  'Note entre 1 et 5': 'Rating must be between 1 and 5',
  'Vous pourrez noter après le trajet': 'You can rate after the ride',
  'Vous ne pouvez pas noter cette personne pour ce trajet': "You can't rate this person for this ride",
  'Avis déjà envoyé': 'Review already sent',
  'Utilisateur introuvable': 'User not found',
};

// ================= TEXTES DE L'APPLICATION (une clé, deux langues) =================
// Le test test/l10n_test.dart vérifie que chaque clé existe en FR et en EN
// et que chaque context.tr('...') du code a bien sa traduction.
const strings = <String, Map<String, String>>{
  'fr': {
    // ---- Splash / connexion ----
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
    'err_unknown': 'Une erreur est survenue',
    'err_open_app': "Impossible d'ouvrir l'application",
    'confirm_password': 'Confirmer le mot de passe',
    'err_pwd_match': 'Les mots de passe ne correspondent pas',
    'pwd_match_ok': 'Les mots de passe correspondent',
    'pwd_weak': 'Faible',
    'pwd_medium': 'Moyen',
    'pwd_strong': 'Fort',

    // ---- Navigation ----
    'tab_search': 'Chercher',
    'tab_post': 'Publier',
    'tab_my_rides': 'Mes trajets',
    'tab_bookings': 'Réservations',
    'tab_profile': 'Profil',
    'ai_help': 'Aide IA',
    'notifications': 'Notifications',
    'offline_banner': 'Hors ligne · données enregistrées affichées',
    'page_not_found': 'Page introuvable',
    'no_page_for': 'Aucune page pour "{name}"',

    // ---- Commun ----
    'yes': 'Oui',
    'no': 'Non',
    'cancel': 'Annuler',
    'send': 'Envoyer',
    'save': 'Enregistrer',
    'retry': 'Réessayer',
    'close': 'Fermer',
    'accept': 'Accepter',
    'decline': 'Refuser',
    'upcoming': 'À venir',
    'history': 'Historique',
    'no_history': 'Aucun historique',
    'new_member': 'Nouveau',
    'name_you': '{name} (vous)',
    'status_pending': 'En attente',
    'status_accepted': 'Acceptée',
    'status_declined': 'Refusée',
    'status_cancelled': 'Annulé',
    'status_open': 'Ouvert',
    'status_done': 'Terminé',

    // ---- Recherche ----
    'destination': 'Destination',
    'date': 'Date',
    'time': 'Heure',
    'max_price': 'Prix max dt',
    'min_seats': 'Places min',
    'search_btn': 'Rechercher',
    'no_rides_found': 'Aucun trajet trouvé.\nEssayez une autre date ou destination.',
    'see_details': 'Voir les détails ›',
    'request_seat': 'Demander une place',
    'seats_left_of': '{left}/{total} places',
    'toast_request_sent': 'Demande envoyée au conducteur',

    // ---- Publier ----
    'post_title': 'Publier un trajet',
    'post_subtitle': 'Proposez vos places libres aux étudiants',
    'departure': 'Départ',
    'seats': 'Places',
    'price_dt': 'Prix (dt)',
    'publish': 'Publier',
    'toast_ride_posted': 'Trajet publié ✅',

    // ---- Validators ----
    'v_required': 'Champ obligatoire',
    'v_min2': '2 caractères minimum',
    'v_same_place': 'La destination doit être différente du départ',
    'v_pick_date': 'Choisissez une date',
    'v_pick_time': "Choisissez l'heure",
    'v_time_past': 'Heure déjà passée',
    'v_integer': 'Nombre entier',
    'v_seats_range': 'Entre 1 et 8',
    'v_number': 'Nombre (ex: 5 ou 4.5)',
    'v_positive': 'Prix positif',
    'v_price_high': 'Prix trop élevé',
    'v_name_required': 'Le nom est obligatoire',
    'v_phone': '8 chiffres (ex: 22123456) ou +216…',
    'v_plate_required': 'Indiquez la plaque de la voiture',
    'v_model_required': 'Indiquez aussi le modèle',
    'v_plate_short': 'Plaque trop courte',

    // ---- Mes trajets / réservations ----
    'no_upcoming_rides': 'Aucun trajet à venir.\nPubliez-en un depuis l\'onglet Publier !',
    'no_upcoming_bookings': 'Aucune réservation à venir.\nCherchez un trajet !',
    'cancel_ride': 'Annuler le trajet',
    'cancel_ride_q': 'Annuler ce trajet ?',
    'cancel_ride_text': 'Les passagers seront prévenus.',
    'tap_to_rate_passengers': 'Touchez pour noter vos passagers',
    'tap_to_rate_driver': 'Touchez pour noter le conducteur',
    'tap_to_call_driver': 'Touchez pour appeler le conducteur',

    // ---- Détails du trajet ----
    'ride_details': 'Détails du trajet',
    'date_at_time': '{date} à {time}',
    'price_per_seat': '{price} dt par place',
    'seats_free': '{left} place(s) libre(s) sur {total}',
    'driver': 'Conducteur',
    'passengers': 'Passagers',
    'requests_and_passengers': 'Demandes et passagers',
    'no_passengers': 'Aucun passager pour le moment',
    'call': 'Appeler',
    'no_phone': 'Pas de numéro dans son profil',
    'call_after_accept': '📞 Vous pourrez appeler le conducteur une fois votre demande acceptée.',
    'wa_to_driver': 'Bonjour {name}, je suis votre passager pour le trajet {route} du {date} à {time} (Campus Carpool).',
    'wa_to_passenger': "Bonjour {name}, c'est votre conducteur pour le trajet {route} du {date} à {time} (Campus Carpool).",
    'how_was_ride': "Comment s'est passé le trajet ?",
    'rate': 'Noter',
    'rate_name': 'Noter {name}',
    'comment_optional': 'Commentaire (facultatif)',
    'stars_1': 'Très mauvais',
    'stars_2': 'Mauvais',
    'stars_3': 'Correct',
    'stars_4': 'Bien',
    'stars_5': 'Excellent',
    'toast_thanks_review': 'Merci pour votre avis ⭐',
    'cancel_booking_q': 'Annuler votre réservation ?',
    'cancel_booking_text': 'Le conducteur sera prévenu.',
    'cancel_request': 'Annuler ma demande',
    'cancel_seat': 'Annuler ma place',
    'full': 'Complet',
    'request_seat_price': 'Demander une place · {price} dt',
    'toast_accepted': 'Passager accepté',
    'toast_declined': 'Demande refusée',
    'toast_ride_cancelled': 'Trajet annulé',
    'toast_booking_cancelled': 'Réservation annulée',
    'reviews_count': 'Avis ({n})',
    'no_reviews': "Pas encore d'avis",
    'route_info': '{km} km · environ {min} min en voiture',
    'route_info_approx': '≈ {km} km à vol d\'oiseau',
    'navigate': 'Itinéraire',

    // ---- Profil ----
    'see_my_reviews': 'Voir mes avis',
    'my_info': 'Mes informations',
    'name': 'Nom',
    'phone': 'Téléphone',
    'phone_helper': 'Visible par vos passagers / conducteurs acceptés',
    'car_model': 'Voiture (modèle, couleur)',
    'plate': 'Plaque',
    'toast_profile_saved': 'Profil enregistré ✅',
    'logout': 'Se déconnecter',
    'settings': 'Paramètres',
    'theme': 'Thème',
    'theme_light': 'Clair',
    'theme_dark': 'Sombre',
    'theme_system': 'Système',
    'language': 'Langue',
    'stat_driver': 'Trajets conducteur',
    'stat_passenger': 'Trajets passager',
    'stat_seats': 'Places partagées',
    'stat_upcoming': 'À venir',
    'stat_rating': 'Ma note',
    'stat_reviews': 'Avis reçus',

    // ---- Notifications ----
    'no_notifications': 'Aucune notification pour le moment',
    'ago_now': "à l'instant",
    'ago_min': 'il y a {n} min',
    'ago_hours': 'il y a {n} h',
    'ago_days': 'il y a {n} j',
    'notif_channel': 'Activité des trajets',
    'notif_channel_desc': 'Réservations, acceptations, annulations et avis',
    'notif_booking_new_title': 'Nouvelle demande',
    'notif_booking_new_body': '{name} demande une place pour {route} ({date} {time}).',
    'notif_booking_accepted_title': 'Réservation acceptée ✅',
    'notif_booking_accepted_body': '{name} a accepté votre demande pour {route} ({date} {time}).',
    'notif_booking_declined_title': 'Réservation refusée',
    'notif_booking_declined_body': '{name} a refusé votre demande pour {route}.',
    'notif_booking_cancelled_title': 'Réservation annulée',
    'notif_booking_cancelled_body': '{name} a annulé sa place pour {route} ({date}).',
    'notif_ride_cancelled_title': 'Trajet annulé',
    'notif_ride_cancelled_body': '{name} a annulé le trajet {route} du {date}.',
    'notif_review_title': 'Nouvel avis ⭐',
    'notif_review_body': '{name} vous a donné {stars}/5 pour {route}.',

    // ---- Assistant ----
    'chat_title': 'Guide du campus',
    'chat_subtitle': 'Guide hors ligne · les réponses restent sur votre téléphone',
    'chat_quick': 'QUESTIONS RAPIDES',
    'chat_hint': 'Posez votre question…',
    'chat_open_section': 'Ouvrir cette section',
    'chat_welcome': 'Bonjour ! Je suis votre guide Campus Carpool. Posez-moi vos questions pour trouver un trajet, réserver une place ou proposer votre propre trajet.',
    'chat_s_find': 'Comment trouver un trajet ?',
    'chat_s_bookings': 'Comment marchent les réservations ?',
    'chat_s_offer': 'Comment proposer un trajet ?',
    'chat_s_profile': 'Comment modifier mon profil ?',
    'chat_a_cancel': 'Un passager peut annuler une demande en attente ou acceptée depuis « Réservations » → « À venir ». Un conducteur peut annuler un trajet à venir depuis « Mes trajets » : les passagers sont prévenus par une notification.',
    'chat_a_empty': "Élargissez la recherche : retirez un filtre, choisissez une autre date, augmentez le prix maximum ou baissez le nombre de places. Seuls les trajets à venir des autres conducteurs s'affichent.",
    'chat_a_offer': 'Touchez « Publier » et indiquez le départ, la destination, la date, l\'heure, les places et le prix en dt. Le trajet apparaît ensuite dans « Mes trajets », où vous acceptez ou refusez les demandes.',
    'chat_a_accept': 'Ouvrez « Mes trajets » : les demandes en attente apparaissent sur le trajet. Touchez la coche verte pour accepter ou la croix rouge pour refuser. Le passager reçoit une notification, et vous pouvez ensuite l\'appeler ou lui écrire sur WhatsApp.',
    'chat_a_booking': 'Quand vous demandez une place, la réservation est « En attente ». Le conducteur l\'accepte ou la refuse et vous recevez une notification. Une fois acceptée, ouvrez le trajet pour appeler le conducteur, puis notez-le après le trajet.',
    'chat_a_account': 'Créez un compte avec votre nom, votre email universitaire et un mot de passe de 6 caractères minimum. Les domaines contenant « univ », .edu ou .ac.* sont acceptés. Déjà inscrit ? Choisissez « Se connecter ».',
    'chat_a_profile': 'Touchez « Profil » pour modifier votre nom, téléphone, voiture ou photo, puis « Enregistrer ». Vous y trouverez aussi vos statistiques, vos avis, le thème sombre et la langue.',
    'chat_a_search': "Touchez « Chercher » : filtrez par destination, date, prix maximum et places minimum, puis « Rechercher ». Touchez un trajet pour voir la carte, le conducteur et sa note, puis « Demander une place ».",
    'chat_a_hello': "Je peux vous aider pour le compte, la recherche de trajets, la publication, les réservations, les annulations, les avis et le profil. Choisissez une suggestion ou posez une question !",
    'chat_a_default': 'Je peux vous aider pour la connexion, la recherche, la publication d\'un trajet, les réservations, les annulations et le profil. Essayez « Comment trouver un trajet ? ».',
  },
  'en': {
    // ---- Splash / login ----
    'tagline': 'Share the road, share the ride',
    'welcome_back': 'Welcome back 👋',
    'create_account': 'Create an account',
    'full_name': 'Full name',
    'uni_email': 'University email',
    'password': 'Password',
    'login': 'Log in',
    'signup': 'Sign up',
    'have_account': 'Already have an account? Log in',
    'no_account': 'No account? Sign up',
    'err_name': 'Enter your full name',
    'err_email_empty': 'Enter your email',
    'err_email_format': 'Invalid email format',
    'err_email_uni': 'Use your university email',
    'err_pwd_empty': 'Enter your password',
    'err_pwd_short': 'Password: at least 6 characters',
    'err_server': 'Server unavailable. Check your connection.',
    'err_unknown': 'Something went wrong',
    'err_open_app': "Couldn't open the app",
    'confirm_password': 'Confirm password',
    'err_pwd_match': 'Passwords do not match',
    'pwd_match_ok': 'Passwords match',
    'pwd_weak': 'Weak',
    'pwd_medium': 'Medium',
    'pwd_strong': 'Strong',

    // ---- Navigation ----
    'tab_search': 'Search',
    'tab_post': 'Post',
    'tab_my_rides': 'My rides',
    'tab_bookings': 'Bookings',
    'tab_profile': 'Profile',
    'ai_help': 'AI help',
    'notifications': 'Notifications',
    'offline_banner': 'Offline · showing saved data',
    'page_not_found': 'Page not found',
    'no_page_for': 'No page for "{name}"',

    // ---- Common ----
    'yes': 'Yes',
    'no': 'No',
    'cancel': 'Cancel',
    'send': 'Send',
    'save': 'Save',
    'retry': 'Retry',
    'close': 'Close',
    'accept': 'Accept',
    'decline': 'Decline',
    'upcoming': 'Upcoming',
    'history': 'History',
    'no_history': 'No history yet',
    'new_member': 'New',
    'name_you': '{name} (you)',
    'status_pending': 'Pending',
    'status_accepted': 'Accepted',
    'status_declined': 'Declined',
    'status_cancelled': 'Cancelled',
    'status_open': 'Open',
    'status_done': 'Completed',

    // ---- Search ----
    'destination': 'Destination',
    'date': 'Date',
    'time': 'Time',
    'max_price': 'Max price dt',
    'min_seats': 'Min seats',
    'search_btn': 'Search',
    'no_rides_found': 'No rides found.\nTry another date or destination.',
    'see_details': 'See details ›',
    'request_seat': 'Request a seat',
    'seats_left_of': '{left}/{total} seats',
    'toast_request_sent': 'Request sent to the driver',

    // ---- Post ----
    'post_title': 'Post a ride',
    'post_subtitle': 'Offer your free seats to other students',
    'departure': 'Departure',
    'seats': 'Seats',
    'price_dt': 'Price (dt)',
    'publish': 'Post',
    'toast_ride_posted': 'Ride posted ✅',

    // ---- Validators ----
    'v_required': 'Required field',
    'v_min2': 'At least 2 characters',
    'v_same_place': 'Destination must differ from departure',
    'v_pick_date': 'Pick a date',
    'v_pick_time': 'Pick a time',
    'v_time_past': 'This time has already passed',
    'v_integer': 'Whole number',
    'v_seats_range': 'Between 1 and 8',
    'v_number': 'Number (e.g. 5 or 4.5)',
    'v_positive': 'Price must be positive',
    'v_price_high': 'Price too high',
    'v_name_required': 'Name is required',
    'v_phone': '8 digits (e.g. 22123456) or +216…',
    'v_plate_required': "Enter the car's plate",
    'v_model_required': 'Enter the car model too',
    'v_plate_short': 'Plate too short',

    // ---- My rides / bookings ----
    'no_upcoming_rides': 'No upcoming rides.\nPost one from the Post tab!',
    'no_upcoming_bookings': 'No upcoming bookings.\nSearch for a ride!',
    'cancel_ride': 'Cancel ride',
    'cancel_ride_q': 'Cancel this ride?',
    'cancel_ride_text': 'Passengers will be notified.',
    'tap_to_rate_passengers': 'Tap to rate your passengers',
    'tap_to_rate_driver': 'Tap to rate the driver',
    'tap_to_call_driver': 'Tap to call the driver',

    // ---- Ride details ----
    'ride_details': 'Ride details',
    'date_at_time': '{date} at {time}',
    'price_per_seat': '{price} dt per seat',
    'seats_free': '{left} of {total} seat(s) free',
    'driver': 'Driver',
    'passengers': 'Passengers',
    'requests_and_passengers': 'Requests and passengers',
    'no_passengers': 'No passengers yet',
    'call': 'Call',
    'no_phone': 'No phone number in their profile',
    'call_after_accept': "📞 You'll be able to call the driver once your request is accepted.",
    'wa_to_driver': "Hi {name}, I'm your passenger for the ride {route} on {date} at {time} (Campus Carpool).",
    'wa_to_passenger': "Hi {name}, I'm your driver for the ride {route} on {date} at {time} (Campus Carpool).",
    'how_was_ride': 'How was the ride?',
    'rate': 'Rate',
    'rate_name': 'Rate {name}',
    'comment_optional': 'Comment (optional)',
    'stars_1': 'Very bad',
    'stars_2': 'Bad',
    'stars_3': 'OK',
    'stars_4': 'Good',
    'stars_5': 'Excellent',
    'toast_thanks_review': 'Thanks for your review ⭐',
    'cancel_booking_q': 'Cancel your booking?',
    'cancel_booking_text': 'The driver will be notified.',
    'cancel_request': 'Cancel my request',
    'cancel_seat': 'Cancel my seat',
    'full': 'Full',
    'request_seat_price': 'Request a seat · {price} dt',
    'toast_accepted': 'Passenger accepted',
    'toast_declined': 'Request declined',
    'toast_ride_cancelled': 'Ride cancelled',
    'toast_booking_cancelled': 'Booking cancelled',
    'reviews_count': 'Reviews ({n})',
    'no_reviews': 'No reviews yet',
    'route_info': '{km} km · about {min} min by car',
    'route_info_approx': '≈ {km} km as the crow flies',
    'navigate': 'Directions',

    // ---- Profile ----
    'see_my_reviews': 'See my reviews',
    'my_info': 'My information',
    'name': 'Name',
    'phone': 'Phone',
    'phone_helper': 'Visible to your accepted passengers / drivers',
    'car_model': 'Car (model, colour)',
    'plate': 'Plate',
    'toast_profile_saved': 'Profile saved ✅',
    'logout': 'Log out',
    'settings': 'Settings',
    'theme': 'Theme',
    'theme_light': 'Light',
    'theme_dark': 'Dark',
    'theme_system': 'System',
    'language': 'Language',
    'stat_driver': 'Rides as driver',
    'stat_passenger': 'Rides as passenger',
    'stat_seats': 'Seats shared',
    'stat_upcoming': 'Upcoming',
    'stat_rating': 'My rating',
    'stat_reviews': 'Reviews received',

    // ---- Notifications ----
    'no_notifications': 'No notifications yet',
    'ago_now': 'just now',
    'ago_min': '{n} min ago',
    'ago_hours': '{n} h ago',
    'ago_days': '{n} d ago',
    'notif_channel': 'Ride activity',
    'notif_channel_desc': 'Bookings, acceptances, cancellations and reviews',
    'notif_booking_new_title': 'New request',
    'notif_booking_new_body': '{name} requested a seat for {route} ({date} {time}).',
    'notif_booking_accepted_title': 'Booking accepted ✅',
    'notif_booking_accepted_body': '{name} accepted your request for {route} ({date} {time}).',
    'notif_booking_declined_title': 'Booking declined',
    'notif_booking_declined_body': '{name} declined your request for {route}.',
    'notif_booking_cancelled_title': 'Booking cancelled',
    'notif_booking_cancelled_body': '{name} cancelled their seat for {route} ({date}).',
    'notif_ride_cancelled_title': 'Ride cancelled',
    'notif_ride_cancelled_body': '{name} cancelled the ride {route} on {date}.',
    'notif_review_title': 'New review ⭐',
    'notif_review_body': '{name} gave you {stars}/5 for {route}.',

    // ---- Assistant ----
    'chat_title': 'Campus guide',
    'chat_subtitle': 'Offline guide · answers stay on your device',
    'chat_quick': 'QUICK QUESTIONS',
    'chat_hint': 'Ask me anything…',
    'chat_open_section': 'Open this section',
    'chat_welcome': "Hi! I'm your Campus Carpool guide. Ask me anything about finding a ride, booking a seat, or sharing your own trip.",
    'chat_s_find': 'How do I find a ride?',
    'chat_s_bookings': 'How do bookings work?',
    'chat_s_offer': 'How do I offer a ride?',
    'chat_s_profile': 'How do I edit my profile?',
    'chat_a_cancel': 'Passengers can cancel a pending or accepted booking from "Bookings" → "Upcoming". Drivers can cancel an upcoming ride from "My rides": passengers get a notification.',
    'chat_a_empty': 'Try broadening your search: remove a filter, choose another date, raise the maximum price or lower the minimum seats. Only upcoming rides from other drivers are shown.',
    'chat_a_offer': 'Tap "Post" and enter your departure, destination, date, time, seats and price in dt. The ride then appears in "My rides", where you accept or decline requests.',
    'chat_a_accept': 'Open "My rides": pending requests appear on the ride. Tap the green check to accept or the red cross to decline. The passenger gets a notification, and you can then call them or message them on WhatsApp.',
    'chat_a_booking': 'When you request a seat, the booking is "Pending". The driver accepts or declines it and you get a notification. Once accepted, open the ride to call the driver, and rate them after the trip.',
    'chat_a_account': 'Create an account with your name, university email and a password of at least 6 characters. Domains containing "univ", .edu or .ac.* are accepted. Already registered? Choose "Log in".',
    'chat_a_profile': 'Tap "Profile" to edit your name, phone, car or photo, then "Save". You will also find your stats, your reviews, dark mode and the language there.',
    'chat_a_search': 'Tap "Search": filter by destination, date, max price and min seats, then "Search". Tap a ride to see the map, the driver and their rating, then "Request a seat".',
    'chat_a_hello': 'I can help with your account, finding rides, posting, bookings, cancellations, reviews and your profile. Pick a suggestion or ask a question!',
    'chat_a_default': 'I can help with signing in, searching, posting a ride, bookings, cancellations and your profile. Try "How do I find a ride?".',
  },
};

/// Petit sélecteur FR | EN (écran de connexion, sur fond indigo si [onDark]).
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
        color: fg.withValues(alpha: 0.15),
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
      onTap: () => context.l10n.setLang(code),
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
