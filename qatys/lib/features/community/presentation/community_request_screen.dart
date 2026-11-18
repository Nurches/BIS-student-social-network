import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/community_repository_provider.dart';
import '../domain/community.dart';
import 'communities_controller.dart';

/// Week 12: the communities the student asked for, with the Student Union's
/// answer (`GET /me/community-requests`).
final myCommunityRequestsProvider = FutureProvider<CommunityRequests>((
  ref,
) async {
  final studentId = ref.watch(
    sessionControllerProvider.select((s) => s.value?.student.id),
  );
  if (studentId == null) return CommunityRequests.empty;
  return ref.read(communityRepositoryProvider).fetchMyRequests();
}, retry: (_, _) => null);

/// Any student asks for a new community. It waits for a moderator of the
/// Student Union; when approved, the student gets a push and publishes its
/// events in the admin panel (BR-01).
class CommunityRequestScreen extends ConsumerStatefulWidget {
  const CommunityRequestScreen({super.key});

  @override
  ConsumerState<CommunityRequestScreen> createState() =>
      _CommunityRequestScreenState();
}

class _CommunityRequestScreenState
    extends ConsumerState<CommunityRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _nameError;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _nameError = null;
      _message = null;
    });
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(communityRepositoryProvider)
          .requestCommunity(
            name: _name.text.trim(),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
          );
      if (!mounted) return;
      switch (result) {
        case CommunityRequestSent(:final request):
          ref
            ..invalidate(myCommunityRequestsProvider)
            ..invalidate(communitiesProvider);
          Navigator.of(context).pop(request);
          return;
        case CommunityNameTaken():
          setState(
            () => _nameError = 'A community with this name already exists.',
          );
        case CommunityRequestLimitReached():
          setState(
            () => _message =
                'You already have 3 requests waiting. Wait for the Student '
                'Union to answer one of them.',
          );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _message = e is NetworkException
            ? 'No connection to the server. Your request is not sent yet.'
            : 'Something went wrong on the server. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requests = ref.watch(myCommunityRequestsProvider).value;
    final left = requests == null
        ? null
        : requests.pendingLimit - requests.pendingCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Request a community')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Steps(),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                // A "name taken" answer is about the old text: clear it on edit.
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'For example: Chess Club',
                  errorText: _nameError,
                ),
                validator: (value) => (value ?? '').trim().length < 3
                    ? 'At least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _description,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'What will it do? (optional)',
                  hintText:
                      'Weekly blitz tournaments and lessons for beginners',
                  alignLabelWithHint: true,
                ),
              ),
              if (left != null) ...[
                const SizedBox(height: 4),
                Text(
                  left <= 0
                      ? 'You have 3 requests waiting — the most at once.'
                      : 'You can send $left more '
                            '${left == 1 ? 'request' : 'requests'} while '
                            'others wait.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_message case final message?) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    key: const ValueKey('request-message'),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Send to the Student Union'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              '$n',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          step(1, 'You send the name and what the community will do.'),
          step(2, 'A Student Union moderator approves or rejects it.'),
          step(
            3,
            'Approved: you get a notification and publish events in the '
            'admin panel. You are the owner.',
          ),
        ],
      ),
    );
  }
}

/// "My requests" on the Explore tab: status and the moderator's reason.
class CommunityRequestTile extends StatelessWidget {
  const CommunityRequestTile({required this.request, super.key});

  final CommunityRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, background, foreground) = switch (request.status) {
      CommunityStatus.pending => (
        'In review',
        Icons.hourglass_top,
        const Color(0xFFFFF1D6),
        const Color(0xFF7A4B00),
      ),
      CommunityStatus.confirmed => (
        'Approved',
        Icons.verified,
        const Color(0xFFDDF3E4),
        const Color(0xFF14532D),
      ),
      CommunityStatus.rejected => (
        'Rejected',
        Icons.block,
        const Color(0xFFFDE2E1),
        const Color(0xFF8A1C1C),
      ),
    };
    final when = request.reviewedAt ?? request.createdAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: foreground),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                switch (request.status) {
                  CommunityStatus.pending =>
                    'Sent ${formatDateTime(when)}. The Student Union answers '
                        'here and with a notification.',
                  CommunityStatus.confirmed =>
                    'Approved ${formatDateTime(when)}. Publish its events in '
                        'the admin panel.',
                  CommunityStatus.rejected =>
                    'Rejected ${formatDateTime(when)}.',
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (request.rejectReason case final reason?) ...[
                const SizedBox(height: 6),
                Text(
                  'Reason: $reason',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
