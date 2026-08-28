import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/settings/presentation/widgets/settings_option_tile.dart';

enum _Choice { a, b, c }

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required Set<_Choice> unavailable,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsOptionTile<_Choice>(
            title: 'Codec',
            subtitle: 'Most compatible — every platform accepts it',
            value: _Choice.a,
            options: _Choice.values,
            unavailable: unavailable,
            // A long combined string — this is what inflated
            // DropdownButton's closed width enough to squeeze the tile's
            // own title/subtitle to almost nothing (see the widget's build()
            // comment) before selectedItemBuilder/menuWidth were added.
            unavailableNote: 'no hardware encoder on this device',
            labelBuilder: (option) => switch (option) {
              _Choice.a => 'H.264 / AVC',
              _Choice.b => 'H.265 / HEVC',
              _Choice.c => 'AV1',
            },
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('title and subtitle stay on one line even with a long unavailable option',
      (tester) async {
    await pumpTile(tester, unavailable: {_Choice.b, _Choice.c});

    // A single line of 14-16sp text is on the order of 20px tall. Before the
    // fix, DropdownButton's closed width was driven by its widest item (the
    // long unavailable-note text) regardless of which was selected, which
    // squeezed this ListTile's title down to near-zero width and wrapped it
    // one letter per line — dozens of lines tall instead of one.
    final titleHeight = tester.getSize(find.text('Codec')).height;
    final subtitleHeight =
        tester.getSize(find.text('Most compatible — every platform accepts it')).height;
    expect(titleHeight, lessThan(50));
    expect(subtitleHeight, lessThan(50));

    // The closed dropdown shows just the short label, not the note.
    expect(find.text('H.264 / AVC'), findsOneWidget);
    expect(find.textContaining('no hardware encoder'), findsNothing);
  });

  testWidgets('opening the menu still shows the unavailable note', (tester) async {
    await pumpTile(tester, unavailable: {_Choice.c});

    await tester.tap(find.text('H.264 / AVC'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no hardware encoder'), findsOneWidget);
  });
}
