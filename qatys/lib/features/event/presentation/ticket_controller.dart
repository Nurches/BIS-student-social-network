import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/local_store.dart';
import '../data/event_json.dart';
import '../data/event_repository_provider.dart';
import '../domain/ticket.dart';

/// The ticket of one event. A ticket that was shown once is saved on the
/// phone: at the door the campus Wi-Fi often asks to sign in first, and the
/// QR must still open. The organiser's scan is what counts, so a saved copy
/// is safe to show.
final ticketProvider = FutureProvider.autoDispose.family<TicketResult, int>((
  ref,
  eventId,
) async {
  final store = ref.read(localStoreProvider);
  final key = 'ticket.$eventId';
  try {
    final result = await ref.read(eventRepositoryProvider).fetchTicket(eventId);
    if (result case TicketReady(:final ticket)) {
      await store.write(key, jsonEncode(ticketToJson(ticket)));
    } else {
      await store.remove(key);
    }
    return result;
  } on NetworkException {
    final saved = await store.read(key);
    if (saved == null) rethrow;
    final json = jsonDecode(saved) as Map<String, Object?>;
    return TicketReady(ticketFromJson(json), offlineCopy: true);
  }
}, retry: (_, _) => null);
