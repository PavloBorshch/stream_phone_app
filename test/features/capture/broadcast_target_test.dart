import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/capture/domain/broadcast_target.dart';

void main() {
  test('toPc includes the PC leg only', () {
    expect(BroadcastTarget.toPc.includesPc, isTrue);
    expect(BroadcastTarget.toPc.includesServices, isFalse);
  });

  test('toServices includes the services leg only', () {
    expect(BroadcastTarget.toServices.includesPc, isFalse);
    expect(BroadcastTarget.toServices.includesServices, isTrue);
  });

  test('both includes both legs', () {
    expect(BroadcastTarget.both.includesPc, isTrue);
    expect(BroadcastTarget.both.includesServices, isTrue);
  });

  test('fromName round-trips every value by its stored name', () {
    for (final value in BroadcastTarget.values) {
      expect(BroadcastTarget.fromName(value.name), value);
    }
  });

  test('fromName falls back to toServices for null/unknown values', () {
    expect(BroadcastTarget.fromName(null), BroadcastTarget.toServices);
    expect(BroadcastTarget.fromName('somethingElse'), BroadcastTarget.toServices);
  });
}
