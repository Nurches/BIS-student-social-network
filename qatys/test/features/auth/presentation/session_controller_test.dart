import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/features/auth/data/auth_providers.dart';
import 'package:qatys/features/auth/data/mock_auth_repository.dart';
import 'package:qatys/features/auth/domain/login_result.dart';
import 'package:qatys/features/auth/presentation/session_controller.dart';

import '../../../helpers/fakes.dart';

void main() {
  late InMemorySessionStorage storage;

  ProviderContainer createContainer() => ProviderContainer.test(
    overrides: [
      sessionStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(
        MockAuthRepository(latency: Duration.zero),
      ),
    ],
  );

  setUp(() => storage = InMemorySessionStorage());

  test('restores a stored session on launch', () async {
    storage.session = sessionExpiringAt(
      DateTime.now().add(const Duration(hours: 1)),
    );

    final session = await createContainer().read(
      sessionControllerProvider.future,
    );

    expect(session?.student.id, 1);
  });

  test('an expired token is cleared instead of restored', () async {
    storage.session = sessionExpiringAt(
      DateTime.now().subtract(const Duration(minutes: 1)),
    );

    final session = await createContainer().read(
      sessionControllerProvider.future,
    );

    expect(session, isNull);
    expect(storage.session, isNull);
  });

  test('a broken keystore starts a clean login', () async {
    storage
      ..session = sessionExpiringAt(
        DateTime.now().add(const Duration(hours: 1)),
      )
      ..failOnRead = true;

    final session = await createContainer().read(
      sessionControllerProvider.future,
    );

    expect(session, isNull);
    expect(storage.session, isNull);
  });

  test('login stores the session, logout removes it', () async {
    final container = createContainer();
    await container.read(sessionControllerProvider.future);
    final controller = container.read(sessionControllerProvider.notifier);

    final result = await controller.login(
      email: 'nurassyl@kbtu.kz',
      password: MockAuthRepository.demoPassword,
    );

    expect(result, isA<LoginSucceeded>());
    expect(storage.session, isNotNull);
    expect(container.read(sessionControllerProvider).value, isNotNull);

    await controller.logout();

    expect(storage.session, isNull);
    expect(container.read(sessionControllerProvider).value, isNull);
  });

  test('failed login stores nothing', () async {
    final container = createContainer();
    await container.read(sessionControllerProvider.future);

    await container
        .read(sessionControllerProvider.notifier)
        .login(email: 'nurassyl@kbtu.kz', password: 'nope');

    expect(storage.session, isNull);
  });
}
