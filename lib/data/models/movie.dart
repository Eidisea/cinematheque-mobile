import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';

/// A poster stored on Cloudinary. [publicId] lets the server replace/delete it later.
class Poster {
  const Poster({required this.url, required this.publicId});

  final String url;
  final String publicId;

  static Poster? fromMap(Object? value) {
    final m = mapOrEmpty(value);
    final url = stringOrNull(m['url']);
    final publicId = stringOrNull(m['publicId']);
    return url == null || publicId == null ? null : Poster(url: url, publicId: publicId);
  }

  Map<String, Object?> toMap() => {'url': url, 'publicId': publicId};
}

/// `movies/{movieId}` — the film catalog. Written by staff (Flutter Web), readable by everyone.
///
/// Genres, directors and cast are simple lists of names inside the movie instead of
/// separate collections: nothing else in the system needs them as their own records.
class Movie {
  const Movie({
    this.id = '',
    required this.title,
    this.synopsis,
    this.runtimeMinutes,
    this.rating,
    this.releaseYear,
    this.genres = const [],
    this.directors = const [],
    this.cast = const [],
    this.poster,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? synopsis;
  final int? runtimeMinutes;
  final String? rating;
  final int? releaseYear;
  final List<String> genres;
  final List<String> directors;
  final List<String> cast;
  final Poster? poster; // null → the UI shows a placeholder; no invented posters
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Movie.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      Movie.fromMap(doc.id, doc.data() ?? const {});

  factory Movie.fromMap(String id, Map<String, dynamic> d) {
    return Movie(
      id: id,
      title: requireString(d['title'], 'title'),
      synopsis: stringOrNull(d['synopsis']),
      runtimeMinutes: intOrNull(d['runtimeMinutes']),
      rating: stringOrNull(d['rating']),
      releaseYear: intOrNull(d['releaseYear']),
      genres: stringList(d['genres']),
      directors: stringList(d['directors']),
      cast: stringList(d['cast']),
      poster: Poster.fromMap(d['poster']),
      createdAt: dateOrNull(d['createdAt']),
      updatedAt: dateOrNull(d['updatedAt']),
    );
  }

  /// Full document for create/replace. Timestamps are set by the Firestore server
  /// (the security rules require it).
  static Map<String, Object?> toFirestore(Movie m, SetOptions? _) => {
        'title': m.title,
        'synopsis': m.synopsis,
        'runtimeMinutes': m.runtimeMinutes,
        'rating': m.rating,
        'releaseYear': m.releaseYear,
        'genres': m.genres,
        'directors': m.directors,
        'cast': m.cast,
        'poster': m.poster?.toMap(),
        'createdAt': m.createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(m.createdAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
