import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rebar_count/editor.dart';
import 'package:rebar_count/models.dart';

void main() {
  testWidgets('Manual count can add, remove, undo and save reviewed markers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picture = img.Image(width: 400, height: 300);
    img.fill(picture, color: img.ColorRgb8(80, 80, 80));
    BundleRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: CountEditor(
          photo: Uint8List.fromList(img.encodePng(picture)),
          onSave: (r) async {
            saved = r;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final photo = find.byType(Image);
    final center = tester.getCenter(photo);
    await tester.tapAt(center);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.tapAt(center);
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo last marker change'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.ensureVisible(find.text('I checked every visible bar end'));
    await tester.tap(find.text('I checked every visible bar end'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save bundle'));
    await tester.tap(find.text('Save bundle'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.marks.length, 1);
    expect(saved!.reviewed, true);
    expect(saved!.diameter, 16);
  });
}
