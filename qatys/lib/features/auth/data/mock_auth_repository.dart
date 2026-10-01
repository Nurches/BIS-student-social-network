import 'dart:convert';

import '../domain/auth_repository.dart';
import '../domain/login_result.dart';
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

  final Map<String, List<DateTime>> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

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

    final student = students.where((s) => s.email == key).firstOrNull;
    if (student == null || password != demoPassword) {
      final recent = (_failures[key] ?? [])
        ..removeWhere((t) => now.difference(t) >= failureWindow)
        ..add(now);
      _failures[key] = recent;
      if (recent.length >= maxFailedAttempts) {
        _failures.remove(key);
        _lockedUntil[key] = now.add(lockDuration);
        return const LoginLocked(retryAfter: lockDuration);
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
