import 'package:flutter/material.dart';

import '../domain/feedback_result.dart';

const ratingWords = ['Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

/// Week 13 (FR-07): rate an event 1–5 with an optional comment. Opened from
/// the event page and from My events, only when the server says the form is
/// open (checked in, the event ended, not rated yet). Returns the answer of
/// [send], or null when the student closed the sheet.
Future<FeedbackResult?> showFeedbackSheet(
  BuildContext context, {
  required String eventTitle,
  required Future<FeedbackResult> Function(int rating, String? comment) send,
}) => showModalBottomSheet<FeedbackResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _FeedbackSheet(eventTitle: eventTitle, send: send),
);

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.eventTitle, required this.send});

  final String eventTitle;
  final Future<FeedbackResult> Function(int rating, String? comment) send;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = _comment.text.trim();
      final result = await widget.send(_rating, text.isEmpty ? null : text);
      if (mounted) Navigator.of(context).pop(result);
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Not sent: no connection to the server. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How was ${widget.eventTitle}?',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'The organiser sees your rating and comment, not your name.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  key: ValueKey('star-$star'),
                  iconSize: 40,
                  tooltip: '$star of 5 — ${ratingWords[star - 1]}',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _rating = star),
                  icon: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: star <= _rating
                        ? const Color(0xFFF59E0B)
                        : theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
          Text(
            _rating == 0 ? 'Tap a star' : ratingWords[_rating - 1],
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('feedback-comment'),
            controller: _comment,
            enabled: !_busy,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'What was good, what to improve',
            ),
          ),
          if (_error case final error?) ...[
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
          ],
          FilledButton(
            key: const ValueKey('feedback-send'),
            onPressed: _rating == 0 || _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('Send rating'),
          ),
          const SizedBox(height: 4),
          Text(
            'A rating cannot be changed after it is sent.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The text shown after the sheet closes.
String feedbackMessage(FeedbackResult result) => switch (result) {
  FeedbackSent(:final rating) =>
    'Thank you! You rated it $rating of 5 (${ratingWords[rating - 1]}).',
  FeedbackNotCheckedIn() =>
    'Only students checked in at the door can rate this event.',
  FeedbackTooEarly() => 'Rating opens when the event ends.',
  FeedbackAlreadySent() => 'You have already rated this event.',
  FeedbackEventCancelled() => 'The event was cancelled, so it cannot be rated.',
};

/// Five star icons for a rating (icons, so they look the same on every phone).
class StarRow extends StatelessWidget {
  const StarRow({required this.rating, this.size = 18, super.key});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$rating of 5 stars',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Icon(
            star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: const Color(0xFFF59E0B),
          ),
      ],
    ),
  );
}
