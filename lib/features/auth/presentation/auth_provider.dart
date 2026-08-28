import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// The signed-in app user, or null if signed out. Reflects Firebase Auth's
/// own state stream, so it updates as soon as sign-in completes.
final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// The email a sign-in link was sent to, kept so the app can complete
/// sign-in without re-prompting when the link is opened on this device.
/// Not a secret — the link itself is the credential — so it lives in
/// [SettingsRepository], not [SecureTokenStore].
final _pendingEmailKey = 'auth_pending_email';

final pendingSignInEmailProvider = Provider<String?>((ref) {
  final json = ref.watch(settingsRepositoryProvider).readJson(_pendingEmailKey);
  return json?['email'] as String?;
});

class EmailLinkSignInController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> sendLink(String email) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).sendSignInLinkToEmail(email);
      await ref.read(settingsRepositoryProvider).writeJson(_pendingEmailKey, {'email': email});
    });
  }

  Future<void> completeSignIn(String link) async {
    final email = ref.read(pendingSignInEmailProvider);
    if (email == null) {
      state = AsyncValue.error(
        StateError('No pending sign-in email on this device for this link.'),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).completeSignInWithEmailLink(email: email, link: link);
      await ref.read(settingsRepositoryProvider).remove(_pendingEmailKey);
    });
  }
}

final emailLinkSignInControllerProvider =
    NotifierProvider<EmailLinkSignInController, AsyncValue<void>>(EmailLinkSignInController.new);

/// Separate from [EmailLinkSignInController] — both buttons are visible on
/// [EmailLoginScreen] at once, so sharing one [AsyncValue] state would make
/// each button's loading/error UI react to the other's requests.
class GoogleSignInController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> signIn() async {
    state = const AsyncValue.loading();
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      state = const AsyncValue.data(null);
    } on GoogleSignInException catch (e, stackTrace) {
      // The user dismissing the account picker isn't an error worth showing.
      state = e.code == GoogleSignInExceptionCode.canceled
          ? const AsyncValue.data(null)
          : AsyncValue.error(e, stackTrace);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }
}

final googleSignInControllerProvider = NotifierProvider<GoogleSignInController, AsyncValue<void>>(
  GoogleSignInController.new,
);
