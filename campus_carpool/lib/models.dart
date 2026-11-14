/// Couche MODÈLE : objets typés de l'application.
/// Chaque document Firestore est converti en objet Dart (fromJson) :
/// autocomplétion, erreurs détectées à la compilation, code plus lisible (ride.price au lieu de ride['price']).
///
/// Un fichier par modèle dans models/ ; ce fichier les réexporte pour un seul import.
library;

export 'models/app_notification.dart';
export 'models/app_user.dart';
export 'models/booking.dart';
export 'models/chat.dart';
export 'models/profile_stats.dart';
export 'models/review.dart';
export 'models/ride.dart';
export 'models/ride_alert.dart';
export 'models/ride_details.dart';
