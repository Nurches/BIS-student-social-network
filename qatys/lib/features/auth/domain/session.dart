import 'dart:convert';

import 'student.dart';

/// A signed-in student and the JWT for API calls.
class Session {
  const Session({required this.token, required this.student});

  final String token;
  final Student student;

  /// The `exp` claim of the JWT, or null if the token cannot be decoded.
  /// The client reads it only to skip a restore that would fail with 401;
  /// the server alone validates the token.
  DateTime? get expiresAt {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map<String, Object?> && payload['exp'] is int) {
        final exp = payload['exp']! as int;
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  bool isExpired(DateTime now) {
    final expiresAt = this.expiresAt;
    return expiresAt != null && !now.isBefore(expiresAt);
  }
}
