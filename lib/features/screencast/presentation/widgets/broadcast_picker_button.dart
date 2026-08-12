import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Wraps iOS's `RPSystemBroadcastPickerView`, the only Apple-sanctioned way to
/// start a third-party ReplayKit broadcast extension. Apple disallows starting
/// a broadcast programmatically, so this native view itself must be the
/// tapped control - there is no Dart-side start/stop call to pair with it.
class BroadcastPickerButton extends StatelessWidget {
  const BroadcastPickerButton({super.key});

  static const double _size = 70;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _size,
      height: _size,
      child: UiKitView(
        viewType: 'com.streamphonecam/broadcast_picker_view',
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}
