import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_token_store.dart';

final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) => const SecureTokenStore());
