/// The app's own identity, distinct from any streaming-platform account
/// (Twitch/Kick, under `features/destinations`). The app has no account
/// system of its own — this just reflects the signed-in Firebase Auth user.
class AuthUser {
  const AuthUser({required this.uid, required this.email});

  final String uid;
  final String? email;
}
