/// Dates for the event cards and the detail screen, without a locale package:
/// the app is English-only for now (brief, section 12).
library;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Tue 20 Nov, 10:00` in device time.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${_weekdays[local.weekday - 1]} ${local.day} '
      '${_months[local.month - 1]}, $hh:$mm';
}

/// `in 3 days`, `in 5 hours`, `in 12 minutes`, or `closed` — next to the
/// deadline, so a student sees the urgency without doing date maths.
String timeLeft(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  if (left <= Duration.zero) return 'closed';
  if (left.inDays >= 1) return 'in ${_plural(left.inDays, 'day')}';
  if (left.inHours >= 1) return 'in ${_plural(left.inHours, 'hour')}';
  return 'in ${_plural(left.inMinutes < 1 ? 1 : left.inMinutes, 'minute')}';
}

String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

/// `just now`, `25 min ago`, `3 h ago`, `yesterday`, `4 days ago`, or the date.
String timeAgo(DateTime value, DateTime now) {
  final ago = now.difference(value);
  if (ago.inMinutes < 1) return 'just now';
  if (ago.inHours < 1) return '${ago.inMinutes} min ago';
  if (ago.inDays < 1) return '${ago.inHours} h ago';
  if (ago.inDays == 1) return 'yesterday';
  if (ago.inDays < 7) return '${ago.inDays} days ago';
  return formatDateTime(value);
}

/// Less than a day left: the card shows the deadline in red.
bool isClosingSoon(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  return left > Duration.zero && left < const Duration(hours: 24);
}
