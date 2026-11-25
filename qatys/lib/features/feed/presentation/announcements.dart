import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/session_controller.dart';
import '../../event/data/event_repository_provider.dart';
import '../../event/domain/event.dart';
import '../../event/presentation/event_detail_screen.dart';
import '../../event/presentation/poster_image.dart';
import 'feed_controller.dart';

/// Week 12: announcement cards on top of the home screen. Open events of
/// every confirmed community, also the ones the student does not follow, so
/// the home screen shows what is happening on campus (`GET /events/announcements`).
final announcementsProvider = FutureProvider<List<Event>>((ref) async {
  final studentId = ref.watch(
    sessionControllerProvider.select((s) => s.value?.student.id),
  );
  if (studentId == null) return const [];
  return ref.read(eventRepositoryProvider).fetchAnnouncements();
}, retry: (_, _) => null);

/// A horizontal carousel of big cards; a tap opens the event page.
/// Hidden when there is nothing to announce or the list cannot be loaded:
/// the feed below has its own messages about the connection.
class AnnouncementsCarousel extends ConsumerStatefulWidget {
  const AnnouncementsCarousel({super.key});

  static const cardHeight = 212.0;

  @override
  ConsumerState<AnnouncementsCarousel> createState() =>
      _AnnouncementsCarouselState();
}

class _AnnouncementsCarouselState extends ConsumerState<AnnouncementsCarousel> {
  final _controller = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final announcements = ref.watch(announcementsProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);

    final items = announcements.value ?? const <Event>[];
    if (announcements.isLoading && items.isEmpty) {
      return const _Placeholder();
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final page = _page.clamp(0, items.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Announcements', style: theme.textTheme.titleLarge),
                    Text(
                      'Happening on campus',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${page + 1} / ${items.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: AnnouncementsCarousel.cardHeight,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 16 : 6,
                right: i == items.length - 1 ? 16 : 6,
              ),
              child: AnnouncementCard(event: items[i], now: now),
            ),
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Dots(count: items.length, current: page),
          ),
      ],
    );
  }
}

/// One announcement: the community's colour, a date tile, the title, where
/// and how many places are left. Semantics read it as one sentence.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({required this.event, required this.now, super.key});

  final Event event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soon = isClosingSoon(event.registrationDeadline, now);
    final places = event.isFull
        ? 'Full · join the waiting list'
        : event.freePlaces == 1
        ? '1 place left'
        : '${event.freePlaces} places left';
    const onCard = Colors.white;
    final onCardMuted = Colors.white.withValues(alpha: 0.86);

    return Semantics(
      button: true,
      label:
          '${event.title}, ${event.communityName}, '
          '${formatDateTime(event.startsAt)}. $places.',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: Ink(
          decoration: BoxDecoration(
            gradient: communityGradient(event.communityId),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EventDetailScreen(eventId: event.id),
              ),
            ),
            child: Stack(
              children: [
                // Week 13 (FR-08): the poster fills the card, under a scrim
                // that keeps the white text readable.
                if (event.hasPoster) ...[
                  Positioned.fill(
                    key: const ValueKey('announcement-poster'),
                    child: PosterImage(
                      path: event.posterUrl,
                      fallback: const SizedBox.shrink(),
                    ),
                  ),
                  const Positioned.fill(child: PosterScrim()),
                ] else
                  // Decoration: a large faded icon in the corner.
                  Positioned(
                    right: -18,
                    bottom: -22,
                    child: Icon(
                      eventIcon(event.title, event.communityName),
                      size: 150,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DateTile(date: event.startsAt),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _GlassPill(text: event.communityName),
                                const SizedBox(height: 8),
                                Text(
                                  '${weekdayShort(event.startsAt)} · '
                                  '${formatTime(event.startsAt)}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: onCardMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: onCard,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (event.location case final location?) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 16,
                              color: onCardMuted,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: onCardMuted),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Flexible(
                            child: _SolidPill(
                              text: places,
                              icon: event.isFull
                                  ? Icons.hourglass_top
                                  : Icons.event_seat_outlined,
                            ),
                          ),
                          if (soon) ...[
                            const SizedBox(width: 8),
                            const Flexible(
                              child: _SolidPill(
                                text: 'Closes today',
                                icon: Icons.timer_outlined,
                                accent: true,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: onCard,
                          ),
                        ],
                      ),
                    ],
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

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Text(
          monthShort(date),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: AppTheme.urgent,
          ),
        ),
        Text(
          '${date.toLocal().day}',
          style: const TextStyle(
            fontSize: 22,
            height: 1.1,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
      ],
    ),
  );
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
    ),
  );
}

class _SolidPill extends StatelessWidget {
  const _SolidPill({
    required this.text,
    required this.icon,
    this.accent = false,
  });

  final String text;
  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final background = accent ? AppTheme.accent : Colors.white;
    const foreground = Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == current ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == current ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 52, 16, 0),
    child: Container(
      height: AnnouncementsCarousel.cardHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
    ),
  );
}
