import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/connection_alert_service.dart';

final connectionAlertServiceProvider = Provider<ConnectionAlertService>(
  (ref) => ConnectionAlertService(),
);
