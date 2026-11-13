import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class RecordStorage {
  Future<List<BundleRecord>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString('bundles-v1');
    return raw == null
        ? []
        : (jsonDecode(raw) as List)
              .map(
                (j) =>
                    BundleRecord.fromJson(Map<String, dynamic>.from(j as Map)),
              )
              .toList();
  }

  Future<void> save(List<BundleRecord> records) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      'bundles-v1',
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
    if (!ok) throw StateError('Storage is full. Export and remove old counts.');
  }
}
