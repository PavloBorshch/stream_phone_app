import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_settings.dart';
import 'package:stream_phone_cam/features/video_settings/presentation/widgets/bitrate_field.dart';

void main() {
  Future<int?> pumpAndSubmit(
    WidgetTester tester, {
    required int initialValue,
    required String typed,
  }) async {
    int? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BitrateField(value: initialValue, onChanged: (value) => reported = value),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), typed);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    return reported;
  }

  testWidgets('shows the initial value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BitrateField(value: 4500, onChanged: _noop)),
      ),
    );

    expect(find.text('4500'), findsOneWidget);
  });

  testWidgets('typing a value and submitting reports the parsed int', (tester) async {
    final reported = await pumpAndSubmit(tester, initialValue: 4500, typed: '6000');
    expect(reported, 6000);
  });

  testWidgets('a value above the max is clamped', (tester) async {
    final reported = await pumpAndSubmit(
      tester,
      initialValue: 4500,
      typed: '${VideoSettings.maxBitrateKbps + 10000}',
    );
    expect(reported, VideoSettings.maxBitrateKbps);
    expect(find.text('${VideoSettings.maxBitrateKbps}'), findsOneWidget);
  });

  testWidgets('a value below the min is clamped', (tester) async {
    final reported = await pumpAndSubmit(tester, initialValue: 4500, typed: '10');
    expect(reported, VideoSettings.minBitrateKbps);
  });

  testWidgets('clearing the field and submitting reverts without reporting a value',
      (tester) async {
    int? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BitrateField(value: 4500, onChanged: (value) => reported = value),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(reported, isNull);
    expect(find.text('4500'), findsOneWidget);
  });

  testWidgets('an external value change updates the field while it is unfocused',
      (tester) async {
    var value = 4500;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BitrateField(value: value, onChanged: (v) => setState(() => value = v)),
                TextButton(
                  onPressed: () => setState(() => value = 9000),
                  child: const Text('bump'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('4500'), findsOneWidget);
    await tester.tap(find.text('bump'));
    await tester.pump();
    expect(find.text('9000'), findsOneWidget);
  });
}

void _noop(int _) {}
