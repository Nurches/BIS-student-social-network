import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../domain/register_result.dart';
import '../domain/student.dart';
import 'session_controller.dart';

/// Create an account with a university email (BR-01). The app signs in with
/// it right away. TODO(confirm): no e-mail code yet (finding A-01).
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _submitting = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    String? error;
    try {
      final result = await ref
          .read(sessionControllerProvider.notifier)
          .register(
            email: _email.text,
            password: _password.text,
            fullName: _name.text,
          );
      error = switch (result) {
        RegisterSignedIn() => null,
        RegisterCreated() => 'Your account was created. Sign in with it.',
        RegisterEmailTaken() =>
          'An account with this email already exists. Sign in instead.',
        RegisterNotUniversityEmail() =>
          'Only university accounts (name@kbtu.kz) can sign up.',
        RegisterBadPassword(:final tooShort) =>
          tooShort
              ? 'The password needs at least 8 characters.'
              : 'The password is too long (at most 72 characters).',
      };
      if (result is RegisterSignedIn) {
        // Signed in: the app root now shows the feed under this screen.
        navigator.popUntil((route) => route.isFirst);
        return;
      }
    } on NetworkException {
      error =
          'No connection to the server. Check the Wi-Fi login page or '
          'switch to mobile data.';
    } on ApiException {
      error = 'Something went wrong on the server. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    InputDecoration field(String label, {String? hint, Widget? suffix}) =>
        InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);

    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Join Qatys with your KBTU email. Then follow the clubs '
                        'you like and never miss a registration again.',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _name,
                        enabled: !_submitting,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: field('Full name', hint: 'Aru Sadykova'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _email,
                        enabled: !_submitting,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: field(
                          'University email',
                          hint: 'name@kbtu.kz',
                        ),
                        validator: (v) {
                          final email = (v ?? '').trim();
                          if (email.isEmpty) {
                            return 'Enter your university email';
                          }
                          return isUniversityEmail(email)
                              ? null
                              : 'Use your university email (name@kbtu.kz)';
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !_submitting,
                        obscureText: !_passwordVisible,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: field(
                          'Password',
                          hint: 'At least 8 characters',
                          suffix: IconButton(
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
                        validator: (v) => (v ?? '').length < 8
                            ? 'At least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _repeat,
                        enabled: !_submitting,
                        obscureText: !_passwordVisible,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: field('Repeat the password'),
                        validator: (v) => v != _password.text
                            ? 'The passwords do not match'
                            : null,
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              error,
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ),
                        ),
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
                            : const Text('Create account'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('I already have an account'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your password is stored only as a bcrypt hash. Five '
                        'wrong passwords lock the account for 15 minutes.',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
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
}
