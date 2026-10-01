import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../data/mock_auth_repository.dart';
import '../domain/login_result.dart';
import '../domain/student.dart';
import 'session_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    String? error;
    try {
      final result = await ref
          .read(sessionControllerProvider.notifier)
          .login(email: _email.text, password: _password.text);
      error = loginErrorMessage(result);
    } on NetworkException {
      error =
          'No connection to the server. Check the Wi-Fi login page '
          'or switch to mobile data.';
    } on ApiException {
      error = 'Something went wrong on the server. Please try again.';
    }

    // On success the app root replaces this screen.
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useMockApi = ref.watch(appConfigProvider).useMockApi;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Qatys', style: theme.textTheme.headlineLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in with your university account',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _email,
                        enabled: !_submitting,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'University email',
                          hintText: 'name@kbtu.kz',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !_submitting,
                        obscureText: !_passwordVisible,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible
                                ? 'Hide password'
                                : 'Show password',
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Enter your password'
                            : null,
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: error),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                      if (useMockApi) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Demo mode: ${MockAuthRepository.students.first.email}'
                          ' / ${MockAuthRepository.demoPassword}',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your university email';
    if (!isUniversityEmail(email)) {
      return 'Use your university email (name@kbtu.kz)';
    }
    return null;
  }
}

/// Message shown under the form, or null when the login succeeded.
String? loginErrorMessage(LoginResult result) => switch (result) {
  LoginSucceeded() => null,
  LoginInvalidCredentials() => 'Wrong email or password.',
  LoginNotUniversityEmail() =>
    'Only university accounts (name@kbtu.kz) can sign in.',
  LoginLocked(:final retryAfter) =>
    'Too many failed attempts. The account is locked. '
        '${_tryAgainIn(retryAfter)}',
};

String _tryAgainIn(Duration? retryAfter) {
  if (retryAfter == null) return 'Try again in 15 minutes.';
  final minutes = math.max(1, (retryAfter.inSeconds / 60).ceil());
  return 'Try again in $minutes ${minutes == 1 ? 'minute' : 'minutes'}.';
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
