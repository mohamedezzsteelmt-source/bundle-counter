import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class RecordStorage {
  RecordStorage({this.directory});
  final Directory? directory;
  Future<File> _file() async => File(
    '${(directory ?? await getApplicationDocumentsDirectory()).path}/bundles-v1.json',
  );
  Future<List<BundleRecord>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    return (jsonDecode(await file.readAsString()) as List)
        .map((j) => BundleRecord.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> save(List<BundleRecord> records) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(records.map((r) => r.toJson()).toList()),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
