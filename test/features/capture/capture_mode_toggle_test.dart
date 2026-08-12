import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/capture/domain/capture_mode.dart';
import 'package:stream_phone_cam/features/capture/presentation/widgets/capture_mode_toggle.dart';

void main() {
  Future<void> pumpToggle(WidgetTester tester, CaptureMode mode, ValueChanged<CaptureMode> onChanged) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptureModeToggle(mode: mode, onChanged: onChanged),
        ),
      ),
    );
  }

  testWidgets('tapping Screencast label reports CaptureMode.screencast', (tester) async {
    CaptureMode? reported;
    await pumpToggle(tester, CaptureMode.camera, (mode) => reported = mode);

    await tester.tap(find.text('Screencast'));
    await tester.pump();

    expect(reported, CaptureMode.screencast);
  });

  testWidgets('tapping Camera label reports CaptureMode.camera', (tester) async {
    CaptureMode? reported;
    await pumpToggle(tester, CaptureMode.screencast, (mode) => reported = mode);

    await tester.tap(find.text('Camera'));
    await tester.pump();

    expect(reported, CaptureMode.camera);
  });
}
