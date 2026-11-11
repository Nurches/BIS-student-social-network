import 'package:flutter/material.dart';

import '../../../core/format/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../domain/event.dart';
import 'event_detail_screen.dart';

/// Brief §7: community, title, start date, deadline, free places — plus the
/// student's own status, a red deadline when less than a day is left and a
/// bar that shows how full the event is.
class EventCard extends StatelessWidget {
  const EventCard({
    required this.event,
    required this.now,
    this.onReturn,
    super.key,
  });

  final Event event;
  final DateTime now;

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EventDetailScreen(eventId: event.id),
              ),
            );
            onReturn?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                  style: theme.textTheme.titleLarge?.copyWith(height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                _Line(
                  icon: Icons.event_outlined,
                  text: 'Starts ${formatDateTime(event.startsAt)}',
                ),
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
                    color: event.isFull ? AppTheme.urgent : colors.onSurface,
                  ),
                ),
              ],
            ),
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
