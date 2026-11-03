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
