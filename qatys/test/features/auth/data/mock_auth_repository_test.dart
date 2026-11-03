import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/features/auth/data/mock_auth_repository.dart';
import 'package:qatys/features/auth/domain/login_result.dart';

void main() {
  late DateTime now;
  late MockAuthRepository repository;

  setUp(() {
    now = DateTime.utc(2026, 10, 1, 12);
    repository = MockAuthRepository(clock: () => now, latency: Duration.zero);
  });

  Future<LoginResult> login(String password, {String? email}) =>
      repository.login(email: email ?? 'nurassyl@kbtu.kz', password: password);

  test('correct password returns a session with a 24-hour token', () async {
    final result = await login(MockAuthRepository.demoPassword);

    final session = (result as LoginSucceeded).session;
    expect(session.student.fullName, 'Turarbek Nurassyl');
    expect(session.expiresAt, now.add(const Duration(hours: 24)));
  });

  test('email is matched case-insensitively and trimmed', () async {
    final result = await login(
      MockAuthRepository.demoPassword,
      email: ' Nurassyl@KBTU.kz ',
    );
    expect(result, isA<LoginSucceeded>());
  });

  test('wrong password is rejected', () async {
    expect(await login('nope'), isA<LoginInvalidCredentials>());
  });

  test('non-university email is rejected', () async {
    expect(
      await login('x', email: 'student@gmail.com'),
      isA<LoginNotUniversityEmail>(),
    );
  });

  test('locks for 15 minutes after 5 failed attempts (NFR-02)', () async {
    for (var i = 0; i < 5; i++) {
      expect(await login('nope'), isA<LoginInvalidCredentials>());
    }
    final sixth = await login('nope');
    expect((sixth as LoginLocked).retryAfter, const Duration(minutes: 15));

    now = now.add(const Duration(minutes: 5));
    final whileLocked = await login(MockAuthRepository.demoPassword);
    expect(
      (whileLocked as LoginLocked).retryAfter,
      const Duration(minutes: 10),
    );

    now = now.add(const Duration(minutes: 10));
    expect(await login(MockAuthRepository.demoPassword), isA<LoginSucceeded>());
  });

  test('failures after the 10-minute window start a new one', () async {
    for (var i = 0; i < 4; i++) {
      await login('nope');
    }
    now = now.add(const Duration(minutes: 10));

    for (var i = 0; i < 4; i++) {
      expect(await login('nope'), isA<LoginInvalidCredentials>());
    }
    expect(await login(MockAuthRepository.demoPassword), isA<LoginSucceeded>());
  });

  test('a successful login resets the failure count', () async {
    for (var i = 0; i < 4; i++) {
      await login('nope');
    }
    expect(await login(MockAuthRepository.demoPassword), isA<LoginSucceeded>());

    for (var i = 0; i < 4; i++) {
      expect(await login('nope'), isA<LoginInvalidCredentials>());
    }
    expect(await login(MockAuthRepository.demoPassword), isA<LoginSucceeded>());
  });
}
