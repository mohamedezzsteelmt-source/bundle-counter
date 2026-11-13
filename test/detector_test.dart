import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rebar_count/detector.dart';
import 'package:rebar_count/models.dart';

Uint8List circles({bool dark = false}) {
  final picture = img.Image(width: 400, height: 300);
  img.fill(
    picture,
    color: img.ColorRgb8(dark ? 230 : 25, dark ? 230 : 25, dark ? 230 : 25),
  );
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 4; col++) {
      img.fillCircle(
        picture,
        x: 50 + col * 95,
        y: 50 + row * 95,
        radius: 18,
        color: img.ColorRgb8(dark ? 25 : 220, dark ? 25 : 220, dark ? 25 : 220),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(picture));
}

void main() {
  test('Finds 12 separated light circular ends with correct coordinates', () {
    final detected = detectBars(DetectionRequest(circles(), 18 / 300, 0.45));
    expect(detected.length, 12);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        expect(
          detected.any(
            (m) =>
                (m.x - (50 + col * 95) / 400).abs() < 0.015 &&
                (m.y - (50 + row * 95) / 300).abs() < 0.015,
          ),
          isTrue,
        );
      }
    }
  });
  test('Finds dark ends against a lighter background', () {
    expect(
      detectBars(DetectionRequest(circles(dark: true), 0.06, 0.45)).length,
      12,
    );
  });
  test('Finds circular ends across a wider range of sizes', () {
    final picture = img.Image(width: 400, height: 300);
    img.fill(picture, color: img.ColorRgb8(25, 25, 25));
    final sizes = [14, 16, 20, 23];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        img.fillCircle(
          picture,
          x: 50 + col * 95,
          y: 50 + row * 95,
          radius: sizes[col],
          color: img.ColorRgb8(220, 220, 220),
        );
      }
    }
    final detected = detectBars(
      DetectionRequest(
        Uint8List.fromList(img.encodePng(picture)),
        18 / 300,
        0.45,
      ),
    );
    expect(detected.length, 12);
  });
  test('Blank photo produces no suggestions', () {
    final picture = img.Image(width: 120, height: 120);
    img.fill(picture, color: img.ColorRgb8(90, 90, 90));
    expect(
      detectBars(
        DetectionRequest(Uint8List.fromList(img.encodePng(picture)), 0.05, 0.5),
      ),
      isEmpty,
    );
  });
  test('Invalid photo fails explicitly', () {
    expect(() => preparePhoto(Uint8List(5)), throwsFormatException);
  });
  test('Normalizes large photo dimensions', () {
    final picture = img.Image(width: 2000, height: 1000);
    final bytes = preparePhoto(Uint8List.fromList(img.encodePng(picture)));
    final decoded = img.decodeImage(bytes)!;
    expect(decoded.width, 1600);
    expect(decoded.height, 800);
  });
  test('Records round trip with marks, photo, review and weight', () {
    final r = BundleRecord(
      id: '1',
      name: 'Bundle A',
      createdAt: DateTime.utc(2026, 1, 1),
      photo: circles(),
      marks: const [BarMark(.1, .2, .03), BarMark(.2, .3, .03)],
      diameter: 16,
      length: 12,
      reviewed: true,
    );
    final restored = BundleRecord.fromJson(r.toJson());
    expect(restored.marks.length, 2);
    expect(restored.photo, r.photo);
    expect(restored.reviewed, true);
    expect(restored.weightKg, closeTo(37.9259, .001));
  });
  test('CSV quotes names, neutralizes formulas and marks samples', () {
    final r = BundleRecord(
      id: '1',
      name: '=SUM(1,2) "x"',
      createdAt: DateTime.utc(2026),
      photo: Uint8List(0),
      marks: [],
      sample: true,
    );
    final csv = recordsCsv([r]);
    expect(csv, contains('"\'=SUM(1,2) ""x"""'));
    expect(csv, contains(',false,true'));
  });
}
