import '../../audit/models/log_entry.dart';

/// Identifies **who** is performing an action.
///
/// This type exists to close a specific hole: before it, [LogActor] was passed
/// around as a plain enum parameter, so any caller could *assert* it was the
/// investigator and have the audit log believe it. Attribution was therefore
/// caller-asserted, not enforced (see `docs/Rules.md` §11).
///
/// The rule now is: **the audit actor is derived from the runtime type of an
/// [ActorContext], never from a value a caller supplies.** [AuditLogger.log]
/// accepts an `ActorContext` and reads [actor] off it. There is no code path
/// that lets a caller name its own actor.
///
/// The hierarchy is `sealed`, so the set of possible actors is closed and the
/// compiler can check exhaustiveness. Privileged mutations (record edits,
/// soft-deletes, media uploads) demand an [InvestigatorContext] specifically —
/// so a call originating on the assistant path, which only ever holds an
/// [AssistantContext], **fails to compile** rather than failing at runtime.
sealed class ActorContext {
  /// The audit actor this context maps to. Fixed per subtype; never settable.
  final LogActor actor;

  const ActorContext._(this.actor);

  /// Stable identifier for the acting subject, recorded in audit payloads.
  String get subjectId;
}

/// The application itself acting without a human in the loop: first-run
/// seeding, index rebuilds, migrations.
///
/// Deliberately cannot perform investigator-gated mutations.
final class SystemContext extends ActorContext {
  const SystemContext() : super._(LogActor.SYSTEM);

  @override
  String get subjectId => 'SYSTEM';
}

/// The LLM assistant acting on the investigator's behalf.
///
/// This is the *only* context the assistant subsystem is ever constructed with
/// (see `ActionGuard`). Because privileged mutations require an
/// [InvestigatorContext], holding this type is what makes the assistant
/// action-boundary a compile-time property instead of a convention.
final class AssistantContext extends ActorContext {
  const AssistantContext() : super._(LogActor.ASSISTANT);

  @override
  String get subjectId => 'ASSISTANT';
}

/// An authenticated human investigator.
///
/// The constructor is private to this library, so a context claiming to be the
/// investigator can only be minted through [issueForSession], which in turn
/// requires an [AuthenticatedSession] — the token auth issues on a successful
/// face/OTP login. Assistant-path code has no session and therefore no way to
/// obtain one.
final class InvestigatorContext extends ActorContext {
  final String investigatorId;
  final String sessionId;

  const InvestigatorContext._({
    required this.investigatorId,
    required this.sessionId,
  }) : super._(LogActor.INVESTIGATOR);

  /// Mints an investigator context from proof of a completed login.
  ///
  /// Takes the session rather than a bare id so that the caller must already
  /// hold something only the auth flow can produce.
  factory InvestigatorContext.issueForSession(AuthenticatedSession session) {
    return InvestigatorContext._(
      investigatorId: session.investigatorId,
      sessionId: session.sessionId,
    );
  }

  @override
  String get subjectId => investigatorId;
}

/// Proof that an investigator completed authentication.
///
/// Constructed only by [AuthSessionIssuer], which the auth module owns. Kept in
/// this library so the privilege boundary is readable in one file.
final class AuthenticatedSession {
  final String investigatorId;
  final String sessionId;
  final DateTime establishedAt;

  const AuthenticatedSession._({
    required this.investigatorId,
    required this.sessionId,
    required this.establishedAt,
  });
}

/// The single mint point for authenticated sessions.
///
/// Auth (face match / verified OTP — `docs/AppFlow.md` §1) calls [issue] after,
/// and only after, a credential check succeeds. It is isolated here so that
/// "what can create investigator privilege" is one greppable call site.
abstract final class AuthSessionIssuer {
  /// Issues a session. **Callers must have already verified a credential.**
  static AuthenticatedSession issue({
    required String investigatorId,
    required String sessionId,
    DateTime? establishedAt,
  }) {
    return AuthenticatedSession._(
      investigatorId: investigatorId,
      sessionId: sessionId,
      establishedAt: establishedAt ?? DateTime.now(),
    );
  }
}
