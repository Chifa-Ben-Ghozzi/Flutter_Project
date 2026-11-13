/// Un avis laissé après un trajet.
class Review {
  final String id;
  final int stars;
  final String comment;
  final String from; // nom de l'auteur
  final String createdAt;

  const Review({required this.id, required this.stars, this.comment = '', this.from = '', this.createdAt = ''});

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: j['id'] ?? '',
        stars: (j['stars'] as num?)?.toInt() ?? 0,
        comment: j['comment'] ?? '',
        from: j['from'] ?? '',
        createdAt: j['createdAt'] ?? '',
      );
}
