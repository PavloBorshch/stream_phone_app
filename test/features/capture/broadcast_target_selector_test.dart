import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/capture/domain/broadcast_target.dart';
import 'package:stream_phone_cam/features/capture/presentation/widgets/broadcast_target_selector.dart';

void main() {
  Future<void> pumpSelector(
    WidgetTester tester,
    BroadcastTarget target,
    ValueChanged<BroadcastTarget> onChanged, {
    bool enabled = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BroadcastTargetSelector(target: target, onChanged: onChanged, enabled: enabled),
        ),
      ),
    );
  }

  testWidgets('shows all three options', (tester) async {
    await pumpSelector(tester, BroadcastTarget.toServices, (_) {});

    expect(find.text('To PC'), findsOneWidget);
    expect(find.text('To services'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);
  });

  testWidgets('tapping "To PC" reports BroadcastTarget.toPc', (tester) async {
    BroadcastTarget? reported;
    await pumpSelector(tester, BroadcastTarget.toServices, (value) => reported = value);

    await tester.tap(find.text('To PC'));
    await tester.pump();

    expect(reported, BroadcastTarget.toPc);
  });

  testWidgets('tapping "Both" reports BroadcastTarget.both', (tester) async {
    BroadcastTarget? reported;
    await pumpSelector(tester, BroadcastTarget.toServices, (value) => reported = value);

    await tester.tap(find.text('Both'));
    await tester.pump();

    expect(reported, BroadcastTarget.both);
  });

  testWidgets('disabled selector ignores taps', (tester) async {
    BroadcastTarget? reported;
    await pumpSelector(tester, BroadcastTarget.toServices, (value) => reported = value, enabled: false);

    await tester.tap(find.text('Both'));
    await tester.pump();

    expect(reported, isNull);
  });
}
