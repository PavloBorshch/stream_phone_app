import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stream_phone_cam/features/auth/data/auth_repository.dart';
import 'package:stream_phone_cam/features/auth/domain/auth_user.dart';
import 'package:stream_phone_cam/features/auth/presentation/auth_provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    final c = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    repository = MockAuthRepository();
  });

  test('signIn() success reflects a data state', () async {
    when(() => repository.signInWithGoogle()).thenAnswer(
      (_) async => const AuthUser(uid: 'u1', email: 'someone@gmail.com'),
    );
    container = buildContainer();

    await container.read(googleSignInControllerProvider.notifier).signIn();

    expect(container.read(googleSignInControllerProvider), const AsyncValue<void>.data(null));
  });

  test('signIn() user-canceled picker stays a data state, not an error', () async {
    when(() => repository.signInWithGoogle()).thenThrow(
      GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    container = buildContainer();

    await container.read(googleSignInControllerProvider.notifier).signIn();

    expect(container.read(googleSignInControllerProvider).hasError, isFalse);
  });

  test('signIn() other failures surface as an error state', () async {
    when(() => repository.signInWithGoogle()).thenThrow(
      GoogleSignInException(code: GoogleSignInExceptionCode.unknownError),
    );
    container = buildContainer();

    await container.read(googleSignInControllerProvider.notifier).signIn();

    expect(container.read(googleSignInControllerProvider).hasError, isTrue);
  });
}
