import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebar_count/detector.dart';
import 'package:rebar_count/models.dart';
import 'package:rebar_count/storage_io.dart';

void main() {
  late Directory dir;
  late RecordStorage storage;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rebar-storage-');
    storage = RecordStorage(directory: dir);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'New store is empty; saved records survive a new instance and deletion',
    () async {
      expect(await storage.load(), isEmpty);
      final r = BundleRecord(
        id: '1',
        name: 'B1',
        createdAt: DateTime.utc(2026),
        photo: Uint8List.fromList([1, 2, 3]),
        marks: const [BarMark(.2, .4, .03)],
      );
      await storage.save([r]);
      final loaded = await RecordStorage(directory: dir).load();
      expect(loaded.single.name, 'B1');
      expect(loaded.single.marks.single.y, .4);
      expect(await File('${dir.path}/bundles-v1.json.tmp').exists(), false);
      await storage.save([]);
      expect(await storage.load(), isEmpty);
    },
  );
  test(
    'Corrupt existing data raises an error instead of silently erasing history',
    () async {
      await File('${dir.path}/bundles-v1.json').writeAsString('broken');
      await expectLater(storage.load(), throwsFormatException);
      expect(
        await File('${dir.path}/bundles-v1.json').readAsString(),
        'broken',
      );
    },
  );
}
