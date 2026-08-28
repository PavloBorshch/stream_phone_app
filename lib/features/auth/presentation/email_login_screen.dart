import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final sendState = ref.watch(emailLinkSignInControllerProvider);
    final pendingEmail = ref.watch(pendingSignInEmailProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: user != null
            ? _SignedIn(email: user.email)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GoogleSignInButton(),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: TextStyle(color: Colors.white54)),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  pendingEmail != null
                      ? _LinkSent(email: pendingEmail)
                      : Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Sign in with your email. No password to set — we send a '
                                'one-time link instead.',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(labelText: 'Email'),
                                validator: (value) {
                                  if (value == null || !value.contains('@')) return 'Enter a valid email';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              if (sendState.hasError)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    'Could not send the link: ${sendState.error}',
                                    style: const TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              FilledButton(
                                onPressed: sendState.isLoading
                                    ? null
                                    : () {
                                        if (_formKey.currentState!.validate()) {
                                          ref
                                              .read(emailLinkSignInControllerProvider.notifier)
                                              .sendLink(_emailController.text.trim());
                                        }
                                      },
                                child: sendState.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Send sign-in link'),
                              ),
                            ],
                          ),
                        ),
                ],
              ),
      ),
    );
  }
}

class _GoogleSignInButton extends ConsumerWidget {
  const _GoogleSignInButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(googleSignInControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Google sign-in failed: ${state.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        OutlinedButton(
          onPressed: state.isLoading
              ? null
              : () => ref.read(googleSignInControllerProvider.notifier).signIn(),
          child: state.isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue with Google'),
        ),
      ],
    );
  }
}

class _LinkSent extends StatelessWidget {
  const _LinkSent({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48, color: Colors.white70),
        const SizedBox(height: 16),
        Text(
          'Check $email for a sign-in link. Opening it on this device signs you in.',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, size: 48, color: Colors.white70),
        const SizedBox(height: 16),
        Text('Signed in as ${email ?? 'unknown'}', style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
