import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/format/date_format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/event.dart';
import '../domain/ticket.dart';
import 'ticket_controller.dart';

/// Week 13 (FR-06): the ticket shown at the door. The organiser scans the QR
/// in /admin, or types the 6-character code under it. Black on white with a
/// quiet zone, so a laptop camera reads it in a dim hall.
class TicketScreen extends ConsumerWidget {
  const TicketScreen({required this.event, super.key});

  /// The event as the previous screen knew it: title, place and time.
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(ticketProvider(event.id));
    Future<void> reload() => ref.refresh(ticketProvider(event.id).future);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket'),
        actions: [
          IconButton(
            tooltip: 'Refresh ticket',
            icon: const Icon(Icons.refresh),
            onPressed: reload,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              switch (ticket) {
                AsyncData(
                  value: TicketReady(:final ticket, :final offlineCopy),
                ) =>
                  _TicketCard(
                    event: event,
                    ticket: ticket,
                    offlineCopy: offlineCopy,
                  ),
                AsyncData(value: TicketWaitingList()) => const _NoTicket(
                  icon: Icons.hourglass_top,
                  title: 'No ticket yet',
                  text:
                      'You are on the waiting list. A ticket appears here as '
                      'soon as a place frees up — you get a notification.',
                ),
                AsyncData(value: TicketEventCancelled()) => const _NoTicket(
                  icon: Icons.event_busy,
                  title: 'Event cancelled',
                  text: 'The organiser cancelled this event. No ticket needed.',
                ),
                AsyncData(value: TicketNotRegistered()) => const _NoTicket(
                  icon: Icons.confirmation_number_outlined,
                  title: 'You are not registered',
                  text:
                      'Register for the event first; the ticket comes with '
                      'a confirmed place.',
                ),
                AsyncError(:final error) => _NoTicket(
                  icon: Icons.cloud_off,
                  title: 'Ticket not loaded',
                  text: error is NetworkException
                      ? 'No connection to the server. Open the ticket once '
                            'while online and it stays on this phone.'
                      : 'Something went wrong on the server. Pull to try again.',
                ),
                _ => const Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.event,
    required this.ticket,
    required this.offlineCopy,
  });

  final Event event;
  final Ticket ticket;
  final bool offlineCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final checkedIn = ticket.checkedInAt;
    final accent = communityColor(event.communityId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offlineCopy)
          Container(
            key: const ValueKey('ticket-offline'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1D6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off, color: Color(0xFF7A4B00)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline copy — it still works at the door.',
                    style: TextStyle(
                      color: Color(0xFF7A4B00),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  gradient: communityGradient(event.communityId),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.communityName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDateTime(event.startsAt)}'
                      '${event.location == null ? '' : ' · ${event.location}'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent, width: 3),
                    ),
                    child: Semantics(
                      label: 'Ticket QR code',
                      image: true,
                      child: QrImageView(
                        key: const ValueKey('ticket-qr'),
                        data: ticket.qr,
                        size: 230,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                'Code',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Semantics(
                label: 'Code ${ticket.code.split('').join(' ')}',
                excludeSemantics: true,
                child: SelectableText(
                  ticket.spacedCode,
                  key: const ValueKey('ticket-code'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: checkedIn != null
                    ? _Banner(
                        key: const ValueKey('ticket-checked-in'),
                        icon: Icons.verified,
                        text: 'Checked in at ${formatTime(checkedIn)}',
                        background: const Color(0xFFDDF3E4),
                        foreground: const Color(0xFF14532D),
                      )
                    : _Banner(
                        icon: Icons.qr_code_scanner,
                        text:
                            'Show this at the door. Check-in opens '
                            '${formatDateTime(ticket.checkInOpensAt)}.',
                        background: const Color(0xFFE3EBF9),
                        foreground: const Color(0xFF0B3D91),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'One ticket lets one person in once. Turn the screen brightness up '
          'if the scanner does not read it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
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

class _NoTicket extends StatelessWidget {
  const _NoTicket({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
