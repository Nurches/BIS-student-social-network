/// Expected outcomes of `POST /events/{id}/feedback` (FR-07, Week 13).
sealed class FeedbackResult {
  const FeedbackResult();
}

/// 201: saved. It cannot be changed afterwards.
final class FeedbackSent extends FeedbackResult {
  const FeedbackSent(this.rating);

  final int rating;
}

/// 403 `not_checked_in`: only a student checked in at the door may rate.
final class FeedbackNotCheckedIn extends FeedbackResult {
  const FeedbackNotCheckedIn();
}

/// 409 `event_not_finished`: the form opens when the event ends.
final class FeedbackTooEarly extends FeedbackResult {
  const FeedbackTooEarly();
}

/// 409 `feedback_already_sent`: one rating per student.
final class FeedbackAlreadySent extends FeedbackResult {
  const FeedbackAlreadySent();
}

/// 409 `event_cancelled`.
final class FeedbackEventCancelled extends FeedbackResult {
  const FeedbackEventCancelled();
}
