import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_user.dart';

/// Wraps Firebase Auth's two sign-in methods — passwordless email-link and
/// Google. The app has no account/password system of its own — Firebase is
/// the identity provider, so there is no server here to run or user
/// database to maintain.
///
/// The email link the user taps must reopen this app (Android App Link /
/// iOS Universal Link back to [_actionUrl]) to complete sign-in — see
/// AndroidManifest.xml's `stream-phone-cam.firebaseapp.com` intent-filter
/// and the `/__/auth/action` route in `app_router.dart`. iOS Associated
/// Domains still needs the real Apple Developer team's verification before
/// this works end-to-end there (same caveat category as the Broadcast
/// Extension App Group placeholders in CLAUDE.md).
///
/// Google sign-in's "Web client (auto created by Google Service)" OAuth
/// client id ([_webClientId] below) is required on **every** platform, not
/// just Android: it's the audience Firebase Auth validates the Google ID
/// token against in `signInWithCredential`. Android's Credential Manager
/// flow additionally needs it passed as `serverClientId` to `initialize()`
/// — without it, or a "Web client" entry (`client_type: 3`) in
/// `google-services.json` for it to auto-read instead, `authenticate()`
/// throws `GoogleSignInExceptionCode.clientConfigurationError`
/// ("serverClientId must be provided on Android"), confirmed against
/// `google_sign_in_android`'s own source (and against a real device — see
/// MISTAKES.md's 2026-08-18 entry). Still outstanding: register the app's
/// debug + release SHA-1 fingerprints (Firebase console → Project Settings
/// → the Android app → Add fingerprint) and replace
/// `android/app/google-services.json` with the re-downloaded version
/// (today's has an empty `oauth_client` array — Android sign-in can't
/// complete without it even with `serverClientId` set). [_iosGoogleClientId]
/// below is the iOS (not Web) OAuth client id, read from
/// `ios/Runner/GoogleService-Info.plist`'s `CLIENT_ID`; its
/// `REVERSED_CLIENT_ID` is registered as a URL scheme in
/// `ios/Runner/Info.plist` for the redirect back into the app.
class AuthRepository {
  AuthRepository([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static const _actionUrl = 'https://stream-phone-cam.firebaseapp.com';

  static const _webClientId =
      '421464515774-sqc5bkfjg4hib6mtsbstl8hotkjeedcc.apps.googleusercontent.com';

  // iOS OAuth client id, from ios/Runner/GoogleService-Info.plist's
  // CLIENT_ID. Its REVERSED_CLIENT_ID is registered as a URL scheme in
  // ios/Runner/Info.plist so the system browser can redirect back into the
  // app after Google sign-in.
  static const _iosGoogleClientId =
      '421464515774-hio994d1r89p2he2vtm90l28c5j88ed6.apps.googleusercontent.com';

  bool _googleSignInInitialized = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS ? _iosGoogleClientId : null,
      serverClientId: _webClientId,
    );
    _googleSignInInitialized = true;
  }

  Stream<AuthUser?> authStateChanges() {
    return _auth.authStateChanges().map(_toAuthUser);
  }

  AuthUser? get currentUser => _toAuthUser(_auth.currentUser);

  Future<void> sendSignInLinkToEmail(String email) {
    return _auth.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: _actionUrl,
        handleCodeInApp: true,
        androidPackageName: 'com.example.stream_phone_cam',
        androidInstallApp: true,
        androidMinimumVersion: '1',
        iOSBundleId: 'com.example.streamPhoneCam',
      ),
    );
  }

  bool isSignInWithEmailLink(String link) => _auth.isSignInWithEmailLink(link);

  Future<AuthUser> completeSignInWithEmailLink({required String email, required String link}) async {
    final credential = await _auth.signInWithEmailLink(email: email, emailLink: link);
    final user = credential.user;
    if (user == null) {
      throw StateError('signInWithEmailLink succeeded but returned no user');
    }
    return _toAuthUser(user)!;
  }

  Future<AuthUser> signInWithGoogle() async {
    await _ensureGoogleSignInInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('signInWithCredential succeeded but returned no user');
    }
    return _toAuthUser(user)!;
  }

  Future<void> signOut() => _auth.signOut();

  AuthUser? _toAuthUser(User? user) {
    if (user == null) return null;
    return AuthUser(uid: user.uid, email: user.email);
  }
}
