import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/event_repository_provider.dart';
import '../domain/event.dart';

/// Events the student is registered for or waiting for (My events tab and
/// the profile numbers). Re-fetched whenever the tab is opened.
final myEventsProvider = FutureProvider<List<Event>>((ref) async {
  final studentId = ref.watch(
    sessionControllerProvider.select((s) => s.value?.student.id),
  );
  if (studentId == null) return const [];
  final events = await ref.read(eventRepositoryProvider).fetchMyEvents();
  return [...events]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}, retry: (_, _) => null);
