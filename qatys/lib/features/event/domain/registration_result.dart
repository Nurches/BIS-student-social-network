/// Expected outcomes of `POST /events/{id}/registrations` (FR-03).
///
/// None of these is an error: a full event or a passed deadline is a normal
/// answer that the UI renders calmly. Transport and auth failures are thrown
/// as `ApiException` instead.
sealed class RegistrationResult {
  const RegistrationResult();
}

/// 201: a confirmed place.
final class RegistrationConfirmed extends RegistrationResult {
  const RegistrationConfirmed();
}

/// 200: the event was full, the student is on the waiting list.
final class RegistrationWaitListed extends RegistrationResult {
  const RegistrationWaitListed({required this.position});

  final int position;
}

/// 409: the student already has a registration for this event.
final class RegistrationAlreadyExists extends RegistrationResult {
  const RegistrationAlreadyExists();
}

/// 410: the registration deadline has passed.
final class RegistrationClosed extends RegistrationResult {
  const RegistrationClosed();
}

/// 409 `event_cancelled`: the organiser cancelled the event.
final class RegistrationEventCancelled extends RegistrationResult {
  const RegistrationEventCancelled();
}

/// Expected outcomes of `DELETE /events/{id}/registrations`.
sealed class CancelResult {
  const CancelResult();
}

/// 200: the place (or the waiting-list entry) is given up.
final class CancelSucceeded extends CancelResult {
  const CancelSucceeded();
}

/// 404 `not_registered`: nothing to cancel, e.g. already cancelled on
/// another device. The screen simply shows the fresh state.
final class CancelNotRegistered extends CancelResult {
  const CancelNotRegistered();
}

/// 410 `event_started`: too late to cancel.
final class CancelEventStarted extends CancelResult {
  const CancelEventStarted();
}

/// 409 `event_cancelled`: the whole event is cancelled; nothing to give up.
final class CancelEventCancelled extends CancelResult {
  const CancelEventCancelled();
}
