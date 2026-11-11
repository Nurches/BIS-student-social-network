import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Round badge with the community's initials in its own colour.
class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    required this.communityId,
    required this.name,
    this.size = 40,
    super.key,
  });

  final int communityId;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = communityColor(communityId);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(
          initials(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}

/// Small rounded label: "Registered ✓", "Waiting list · #2", "Closes today".
class Pill extends StatelessWidget {
  const Pill({
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
    super.key,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ],
    ),
  );
}

/// How full an event is; red once nothing is left.
class CapacityBar extends StatelessWidget {
  const CapacityBar({required this.freePlaces, required this.limit, super.key});

  final int freePlaces;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final taken = limit <= 0
        ? 1.0
        : ((limit - freePlaces) / limit).clamp(0.0, 1.0);
    final color = freePlaces <= 0
        ? AppTheme.urgent
        : taken >= 0.8
        ? const Color(0xFFE08A00)
        : colors.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: taken,
        minHeight: 6,
        color: color,
        backgroundColor: colors.surfaceContainerHighest,
      ),
    );
  }
}

/// Icon, title, one sentence and an optional button — for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 42,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel case final label?) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    );
  }
}

/// Bold section title above a group of cards.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A full-screen message with a retry button, for a first load that failed.
class LoadFailure extends StatelessWidget {
  const LoadFailure({required this.message, required this.onRetry, super.key});

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
