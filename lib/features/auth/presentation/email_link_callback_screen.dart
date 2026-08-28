import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_provider.dart';

/// Landing screen for the email sign-in link (`/__/auth/action`, the
/// Firebase-hosted action URL — see AuthRepository._actionUrl). Reached
/// only if the OS actually reopens the app for that https link, which
/// requires the Android App Link / iOS Universal Link verification steps
/// flagged in AuthRepository's doc comment.
class EmailLinkCallbackScreen extends ConsumerStatefulWidget {
  const EmailLinkCallbackScreen({required this.link, super.key});

  final String link;

  @override
  ConsumerState<EmailLinkCallbackScreen> createState() => _EmailLinkCallbackScreenState();
}

class _EmailLinkCallbackScreenState extends ConsumerState<EmailLinkCallbackScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    await ref.read(emailLinkSignInControllerProvider.notifier).completeSignIn(widget.link);
    if (mounted) context.go('/settings/account');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailLinkSignInControllerProvider);
    return Scaffold(
      body: Center(
        child: state.hasError
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sign-in failed: ${state.error}',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
