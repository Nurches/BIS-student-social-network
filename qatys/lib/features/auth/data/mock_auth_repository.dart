import 'dart:convert';

import '../domain/auth_repository.dart';
import '../domain/login_result.dart';
import '../domain/register_result.dart';
import '../domain/session.dart';
import '../domain/student.dart';

/// In-memory [AuthRepository] that behaves like the server in docs/api.md,
/// including the NFR-02 lockout. Accounts are the students seeded in
/// docs/schema.sql; all of them use [demoPassword].
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 400),
  }) : _now = clock ?? DateTime.now;

  static const demoPassword = 'qatys2026';
  static const maxFailedAttempts = 5;
  static const failureWindow = Duration(minutes: 10);
  static const lockDuration = Duration(minutes: 15);

  static const students = [
    Student(id: 1, email: 'nurassyl@kbtu.kz', fullName: 'Turarbek Nurassyl'),
    Student(id: 2, email: 'akbota@kbtu.kz', fullName: 'Nurkasymova Akbota'),
    Student(id: 3, email: 'laila@kbtu.kz', fullName: 'Taubay Laila'),
    Student(id: 4, email: 'madina@kbtu.kz', fullName: 'Shpanova Madina'),
    Student(id: 5, email: 'gulnazym@kbtu.kz', fullName: 'Ualikhan Gulnazym'),
    Student(id: 6, email: 'union@kbtu.kz', fullName: 'Student Union Staff'),
  ];

  final DateTime Function() _now;
  final Duration latency;

  /// Open failure window per email, as `failed_logins` and
  /// `first_failed_login_at` in docs/schema.sql.
  final Map<String, ({DateTime since, int count})> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  /// Accounts created with [register] while the app runs.
  final Map<String, ({Student student, String password})> _registered = {};

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await Future<void>.delayed(latency);
    final key = email.trim().toLowerCase();
    if (!isUniversityEmail(key)) return const RegisterNotUniversityEmail();
    if (password.length < 8) return const RegisterBadPassword(tooShort: true);
    if (utf8.encode(password).length > 72) {
      return const RegisterBadPassword(tooShort: false);
    }
    if (_registered.containsKey(key) || students.any((s) => s.email == key)) {
      return const RegisterEmailTaken();
    }
    _registered[key] = (
      student: Student(
        id: 100 + _registered.length,
        email: key,
        fullName: fullName.trim(),
      ),
      password: password,
    );
    return const RegisterCreated();
  }

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    if (!isUniversityEmail(email)) return const LoginNotUniversityEmail();

    final now = _now();
    final key = email.trim().toLowerCase();

    final lockedUntil = _lockedUntil[key];
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      return LoginLocked(retryAfter: lockedUntil.difference(now));
    }

    final created = _registered[key];
    final student =
        created?.student ?? students.where((s) => s.email == key).firstOrNull;
    final expected = created?.password ?? demoPassword;
    if (student == null || password != expected) {
      // The first failure opens a 10-minute window; the 5th failure inside it
      // still answers 401 but sets the lock, so the 6th attempt sees 423.
      final open = _failures[key];
      final failures =
          open != null && now.difference(open.since) < failureWindow
          ? (since: open.since, count: open.count + 1)
          : (since: now, count: 1);
      if (failures.count >= maxFailedAttempts) {
        _failures.remove(key);
        _lockedUntil[key] = now.add(lockDuration);
      } else {
        _failures[key] = failures;
      }
      return const LoginInvalidCredentials();
    }

    _failures.remove(key);
    return LoginSucceeded(
      Session(token: _fakeJwt(student, now), student: student),
    );
  }

  /// Unsigned token with a real `exp` claim, so expiry handling works the
  /// same way as with the server's 24-hour JWT.
  String _fakeJwt(Student student, DateTime now) {
    String encode(Map<String, Object> json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

    final exp = now.add(const Duration(hours: 24)).millisecondsSinceEpoch;
    return [
      encode({'alg': 'none', 'typ': 'JWT'}),
      encode({'sub': '${student.id}', 'exp': exp ~/ 1000}),
      'mock',
    ].join('.');
  }
}
