/// Typed failures for the boundaries that can realistically fail at runtime:
/// the local LLM server, the database, and the file system.
///
/// Before this, DB and network calls were unguarded and a single throw
/// surfaced as a blank screen with no explanation - the worst outcome
/// mid-demo. Each type carries a message safe to show an investigator.
sealed class AppException implements Exception {
  /// Message intended for display in the UI.
  final String message;

  /// Underlying error, retained for diagnostics. Never rendered raw.
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// The Ollama server could not be reached at all - not installed, not
/// running, or the configured base URL is wrong.
final class LlmUnavailableException extends AppException {
  final String baseUrl;

  LlmUnavailableException(this.baseUrl, {super.cause})
      : super('Cannot reach the local model server at $baseUrl. '
            'Check that Ollama is running, then try again.');
}

/// Ollama answered, but not successfully (bad request, model load failure,
/// out of memory).
final class LlmRequestException extends AppException {
  final int? statusCode;

  const LlmRequestException(super.message, {this.statusCode, super.cause});
}

/// A generation exceeded its time budget.
final class LlmTimeoutException extends AppException {
  final Duration budget;

  LlmTimeoutException(this.budget)
      : super('The model did not respond within ${budget.inSeconds}s. '
            'It may still be loading - try again, or point OLLAMA_BASE_URL '
            'at a faster machine.');
}

/// A model the app depends on is not present on the Ollama server.
final class LlmModelMissingException extends AppException {
  final String model;

  LlmModelMissingException(this.model)
      : super('Model "$model" is not available on the Ollama server. '
            'Pull it with:  ollama pull $model');
}

/// Persistence failed.
final class DataAccessException extends AppException {
  const DataAccessException(super.message, {super.cause});
}

/// An assistant action was refused by the ActionGuard.
///
/// Raised when the assistant requests a capability it does not have. The
/// message is written to be shown back to the investigator verbatim, so the
/// boundary is visible rather than silent.
final class ActionNotPermittedException extends AppException {
  /// The capability that was requested and denied.
  final String attemptedAction;

  ActionNotPermittedException(this.attemptedAction)
      : super('The assistant is not permitted to perform "$attemptedAction". '
            'It can only create case notes; criminal records and images can '
            'be changed by the investigator alone.');
}
