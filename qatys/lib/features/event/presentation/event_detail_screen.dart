import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../../community/presentation/community_screen.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../sync/domain/pending_action.dart';
import '../../sync/presentation/pending_actions_controller.dart';
import '../domain/event.dart';
import 'event_detail_controller.dart';

/// Brief §7 and §8: the deadline, the free places and the action button fit
/// on a 320 dp wide phone without scrolling, and the action sits in the
/// bottom third, reachable with a thumb. Only the description scrolls.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({required this.eventId, super.key});

  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = eventDetailProvider(eventId);
    final detail = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(provider.notifier).refresh(),
          ),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _Body(state: value, eventId: eventId),
        AsyncError(:final error) => _LoadError(
          message: switch (error) {
            String() => error,
            NotFoundException() => 'This event is no longer published.',
            NetworkException() =>
              'No connection to the server. Check the Wi-Fi login page '
                  'or switch to mobile data.',
            _ => 'Something went wrong on the server. Please try again.',
          },
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.eventId});

  final EventDetailState state;
  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final event = state.event;
    final now = ref.watch(clockProvider)();
    final pending = ref
        .watch(pendingActionsProvider)
        .value
        ?.where((a) => a.eventId == eventId)
        .firstOrNull;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(event: event),
          if (event.isCancelled)
            const _Notice(
              key: ValueKey('cancelled-notice'),
              icon: Icons.event_busy,
              text:
                  'Cancelled by the organiser. It will not take place; '
                  'nothing else to do.',
              background: Color(0xFFFDE2E1),
              foreground: Color(0xFF8A1C1C),
            )
          else if (event.previousStartsAt case final before?)
            _Notice(
              key: const ValueKey('moved-notice'),
              icon: Icons.update,
              text:
                  'Moved to ${formatDateTime(event.startsAt)} '
                  '(was ${formatDateTime(before)}).',
              background: const Color(0xFFFFF1D6),
              foreground: const Color(0xFF7A4B00),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A cancelled event: registration numbers no longer matter.
                if (!event.isCancelled) ...[
                  _Fact(
                    icon: Icons.timer_outlined,
                    label: 'Register by',
                    value:
                        '${formatDateTime(event.registrationDeadline)} '
                        '(${timeLeft(event.registrationDeadline, now)})',
                    key: const ValueKey('deadline'),
                    highlight:
                        isClosingSoon(event.registrationDeadline, now) ||
                            event.isDeadlinePassed(now)
                        ? AppTheme.urgent
                        : null,
                  ),
                  _Fact(
                    icon: Icons.event_seat_outlined,
                    label: 'Free places',
                    value: event.isFull
                        ? 'None — waiting list open'
                        : '${event.freePlaces} of ${event.participantLimit}',
                    key: const ValueKey('free-places'),
                    highlight: event.isFull ? AppTheme.urgent : null,
                  ),
                ],
                _Fact(
                  icon: Icons.schedule,
                  label: 'Starts',
                  value: formatDateTime(event.startsAt),
                ),
                if (event.location case final location?)
                  _Fact(
                    icon: Icons.place_outlined,
                    label: 'Where',
                    value: location,
                  ),
                if (!event.isCancelled) ...[
                  const SizedBox(height: 8),
                  CapacityBar(
                    freePlaces: event.freePlaces,
                    limit: event.participantLimit,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                event.description.isEmpty
                    ? 'No description.'
                    : event.description,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The answer to the last tap sits right above the button: a
                  // snackbar would cover the button in the bottom third.
                  if (state.message case final message?) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        key: const ValueKey('action-message'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _Action(
                    state: state,
                    pending: pending,
                    now: now,
                    eventId: eventId,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The coloured header: community (opens its page), title, date tile.
class _Hero extends StatelessWidget {
  const _Hero({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = event.isCancelled
        ? const LinearGradient(colors: [Color(0xFF6B7280), Color(0xFF374151)])
        : communityGradient(event.communityId);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -14,
            bottom: -20,
            child: Icon(
              eventIcon(event.title, event.communityName),
              size: 120,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The community opens its own page: follow it from there.
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CommunityScreen(communityId: event.communityId),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: CommunityAvatar(
                            communityId: event.communityId,
                            name: event.communityName,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            event.communityName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  event.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    height: 1.15,
                    decoration: event.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: Colors.white,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Red for a deadline under a day and for a full event.
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: (highlight ?? theme.colorScheme.primary).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 17,
              color: highlight ?? theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: highlight,
                      fontWeight: highlight == null ? null : FontWeight.w700,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The button states of brief §7: Register / Join waiting list /
/// Registered ✓ with cancel / Registration closed — plus the waiting-list
/// status and a tap still waiting in the offline queue.
class _Action extends ConsumerWidget {
  const _Action({
    required this.state,
    required this.pending,
    required this.now,
    required this.eventId,
  });

  final EventDetailState state;
  final PendingAction? pending;
  final DateTime now;
  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(eventDetailProvider(eventId).notifier);
    final event = state.event;
    final busy = state.busy;
    final started = !now.isBefore(event.startsAt);

    Widget primary(String label, VoidCallback onPressed) => FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy ? const _Progress() : Text(label),
    );

    Widget secondary(String label, VoidCallback onPressed) => OutlinedButton(
      onPressed: busy ? null : onPressed,
      child: busy ? const _Progress() : Text(label),
    );

    if (event.isCancelled) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.event_busy),
        label: Text(
          event.myState == RegistrationState.none
              ? 'Event cancelled'
              : 'Event cancelled · your place is released',
        ),
      );
    }

    if (pending case final pending?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Status(
            icon: Icons.cloud_off,
            text: pending.kind == PendingKind.register
                ? 'Registration saved offline — not sent yet.'
                : 'Cancellation saved offline — not sent yet.',
          ),
          const SizedBox(height: 8),
          primary('Send now', controller.refresh),
          TextButton(
            onPressed: busy ? null : controller.undoPending,
            child: const Text('Undo'),
          ),
        ],
      );
    }

    return switch (event.myState) {
      RegistrationState.registered => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Status(
            icon: Icons.check_circle,
            text: 'Registered ✓',
            tone: _Status.confirmed,
          ),
          if (!started) ...[
            const SizedBox(height: 8),
            secondary(
              'Cancel registration',
              () => _confirmCancel(context, controller),
            ),
          ],
        ],
      ),
      RegistrationState.waitingList => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Status(
            icon: Icons.hourglass_top,
            tone: _Status.waiting,
            text: event.waitingPosition == null
                ? 'You are on the waiting list.'
                : 'You are number ${event.waitingPosition} on the waiting list.',
          ),
          if (!started) ...[
            const SizedBox(height: 8),
            secondary('Leave waiting list', controller.cancel),
          ],
        ],
      ),
      RegistrationState.none when event.isDeadlinePassed(now) =>
        const FilledButton(onPressed: null, child: Text('Registration closed')),
      RegistrationState.none when event.isFull => primary(
        'Join waiting list',
        controller.register,
      ),
      RegistrationState.none => primary('Register', controller.register),
    };
  }

  Future<void> _confirmCancel(
    BuildContext context,
    EventDetailController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel your registration?'),
        content: const Text(
          'Your place goes to the next student on the waiting list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep my place'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel registration'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.cancel();
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;

  /// Green for a confirmed place, amber for the waiting list.
  final ({Color background, Color foreground})? tone;

  static const confirmed = (
    background: Color(0xFFDDF3E4),
    foreground: Color(0xFF14532D),
  );
  static const waiting = (
    background: Color(0xFFFFF1D6),
    foreground: Color(0xFF7A4B00),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = tone?.background ?? colors.secondaryContainer;
    final foreground = tone?.foreground ?? colors.onSecondaryContainer;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 24,
    child: CircularProgressIndicator(strokeWidth: 3),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
