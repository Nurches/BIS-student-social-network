import 'package:flutter/material.dart';

import '../../../core/format/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../domain/event.dart';
import 'event_detail_screen.dart';
import 'poster_image.dart';

/// Brief §7: community, title, start date, deadline, free places — plus the
/// student's own status, a red deadline when less than a day is left and a
/// bar that shows how full the event is.
class EventCard extends StatelessWidget {
  const EventCard({
    required this.event,
    required this.now,
    this.onReturn,
    this.footer,
    super.key,
  });

  final Event event;
  final DateTime now;

  /// Week 13: an action under the card, e.g. "Show ticket" in My events.
  final Widget? footer;

  /// Called when the student comes back from the detail screen, so the list
  /// can show what changed there.
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final soon = isClosingSoon(event.registrationDeadline, now);
    final closed = event.isDeadlinePassed(now);

    final status = switch (event.myState) {
      _ when event.isCancelled => const Pill(
        text: 'Cancelled',
        icon: Icons.event_busy,
        background: Color(0xFFFDE2E1),
        foreground: Color(0xFF8A1C1C),
      ),
      RegistrationState.registered => const Pill(
        text: 'Registered ✓',
        background: Color(0xFFDDF3E4),
        foreground: Color(0xFF14532D),
      ),
      RegistrationState.waitingList => Pill(
        text: event.waitingPosition == null
            ? 'Waiting list'
            : 'Waiting list · #${event.waitingPosition}',
        icon: Icons.hourglass_top,
        background: const Color(0xFFFFF1D6),
        foreground: const Color(0xFF7A4B00),
      ),
      RegistrationState.none => null,
    };

    final accent = communityColor(event.communityId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: BorderSide(color: colors.outlineVariant),
        ),
        shadowColor: accent.withValues(alpha: 0.25),
        elevation: event.isCancelled ? 0 : 1.5,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EventDetailScreen(eventId: event.id),
              ),
            );
            onReturn?.call();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Week 13 (FR-08): the poster on top, when the event has one.
              if (event.hasPoster)
                AspectRatio(
                  key: const ValueKey('card-poster'),
                  aspectRatio: 2,
                  child: PosterImage(
                    path: event.posterUrl,
                    fallback: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: communityGradient(event.communityId),
                      ),
                    ),
                  ),
                ),
              DecoratedBox(
                // A stripe in the community's colour: the club at a glance.
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: event.isCancelled ? colors.outline : accent,
                      width: 5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CommunityAvatar(
                            communityId: event.communityId,
                            name: event.communityName,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              event.communityName,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ?status,
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        event.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          height: 1.2,
                          decoration: event.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                          color: event.isCancelled
                              ? colors.onSurfaceVariant
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      _Line(
                        icon: Icons.event_outlined,
                        text: 'Starts ${formatDateTime(event.startsAt)}',
                      ),
                      if (event.previousStartsAt case final before?
                          when !event.isCancelled) ...[
                        const SizedBox(height: 4),
                        _Line(
                          icon: Icons.update,
                          text: 'Moved · was ${formatDateTime(before)}',
                          color: const Color(0xFF7A4B00),
                          bold: true,
                        ),
                      ],
                      if (event.isCancelled) ...[
                        const SizedBox(height: 4),
                        const _Line(
                          icon: Icons.info_outline,
                          text: 'The organiser cancelled this event.',
                          color: Color(0xFF8A1C1C),
                          bold: true,
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        _Line(
                          icon: Icons.timer_outlined,
                          text:
                              'Register by ${formatDateTime(event.registrationDeadline)} '
                              '(${timeLeft(event.registrationDeadline, now)})',
                          color: soon || closed ? AppTheme.urgent : null,
                          bold: true,
                        ),
                        const SizedBox(height: 12),
                        CapacityBar(
                          freePlaces: event.freePlaces,
                          limit: event.participantLimit,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          event.isFull
                              ? 'Full · waiting list open'
                              : '${event.freePlaces} of ${event.participantLimit} '
                                    'places free',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: event.isFull
                                ? AppTheme.urgent
                                : colors.onSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (footer case final footer?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.text,
    this.color,
    this.bold = false,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color ?? muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
