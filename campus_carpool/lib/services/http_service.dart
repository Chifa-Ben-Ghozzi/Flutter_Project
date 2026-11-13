import 'package:http/http.dart' as http;

/// Client HTTP partagé pour les services externes (géocodage, itinéraire).
class HttpService {
  /// Remplaçable dans les tests par un MockClient (package:http/testing.dart).
  static http.Client client = http.Client();
}
