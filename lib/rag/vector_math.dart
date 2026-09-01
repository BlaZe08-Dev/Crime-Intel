import 'dart:math' as math;

/// Vector similarity used by the retrieval step.
///
/// **Why this is in Dart rather than sqlite-vec.** sqlite-vec would mean
/// loading a platform-specific native extension into `sqflite_common_ffi` and
/// shipping that DLL alongside the Windows build — a binary dependency and a
/// packaging risk for a demo that has to run from a zip on someone else's
/// machine. The synthetic corpus is on the order of a hundred chunks, where a
/// linear scan of 768-dimensional vectors costs well under a millisecond, so
/// the index buys nothing we need. If the corpus ever grows past a few
/// thousand chunks, swap [VectorMath.rank] for an ANN index behind the same
/// call — nothing above it depends on the scan being linear.
abstract final class VectorMath {
  /// Cosine similarity in the range [-1, 1]; 1 means identical direction.
  ///
  /// Returns 0 for empty, length-mismatched, or zero-magnitude inputs — those
  /// mean "no usable signal", and 0 sorts below any real match rather than
  /// throwing mid-query.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      dot += x * y;
      normA += x * x;
      normB += y * y;
    }

    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  /// Scores [candidates] against [query] and returns them best-first.
  ///
  /// Only entries scoring at least [minScore] survive, and at most [topK] are
  /// returned. An empty result is meaningful: it is what makes the assistant
  /// say "not in the database" instead of guessing (`docs/Rules.md` §4).
  static List<ScoredItem<T>> rank<T>({
    required List<double> query,
    required List<T> candidates,
    required List<double> Function(T) vectorOf,
    required int topK,
    required double minScore,
  }) {
    if (query.isEmpty || candidates.isEmpty || topK <= 0) return const [];

    final scored = <ScoredItem<T>>[];
    for (final candidate in candidates) {
      final score = cosineSimilarity(query, vectorOf(candidate));
      if (score >= minScore) {
        scored.add(ScoredItem(item: candidate, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.length <= topK ? scored : scored.sublist(0, topK);
  }
}

/// An item paired with its relevance score.
class ScoredItem<T> {
  final T item;
  final double score;

  const ScoredItem({required this.item, required this.score});

  @override
  String toString() => 'ScoredItem(${score.toStringAsFixed(3)})';
}
