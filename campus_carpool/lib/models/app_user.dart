import 'json_utils.dart';
import 'review.dart';

/// Un utilisateur : profil, voiture, note moyenne.
class AppUser {
  final String id;
  final String name;
  final String? email; // seulement pour l'utilisateur connecté
  final String phone;
  final String carModel;
  final String carPlate;
  final String? photo; // image en base64
  final double? rating; // null = pas encore d'avis
  final int ratingCount;
  final List<Review> reviews; // seulement dans le profil public

  const AppUser({
    required this.id,
    required this.name,
    this.email,
    this.phone = '',
    this.carModel = '',
    this.carPlate = '',
    this.photo,
    this.rating,
    this.ratingCount = 0,
    this.reviews = const [],
  });

  bool get hasCar => carModel.isNotEmpty;
  bool get hasPhone => phone.trim().isNotEmpty;
  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final car = Map<String, dynamic>.from(j['car'] ?? const {});
    return AppUser(
      id: j['id'] ?? '',
      name: j['name'] ?? '',
      email: j['email'],
      phone: j['phone'] ?? '',
      carModel: car['model'] ?? '',
      carPlate: car['plate'] ?? '',
      photo: j['photo'],
      rating: toDoubleOrNull(j['rating']),
      ratingCount: j['ratingCount'] ?? 0,
      reviews: listOf(j['reviews'], Review.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'car': {'model': carModel, 'plate': carPlate},
        'photo': photo,
        'rating': rating,
        'ratingCount': ratingCount,
      };
}
