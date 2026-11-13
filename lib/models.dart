import 'dart:convert';
import 'dart:typed_data';
import 'detector.dart';

class BundleRecord {
  BundleRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.photo,
    required this.marks,
    this.diameter = 16,
    this.length = 12,
    this.reviewed = false,
    this.sample = false,
  });
  final String id, name;
  final DateTime createdAt;
  final Uint8List photo;
  final List<BarMark> marks;
  final double diameter, length;
  final bool reviewed, sample;
  double get weightKg => marks.length * diameter * diameter / 162 * length;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'photo': base64Encode(photo),
    'marks': marks.map((m) => m.toJson()).toList(),
    'diameter': diameter,
    'length': length,
    'reviewed': reviewed,
    'sample': sample,
  };
  factory BundleRecord.fromJson(Map<String, dynamic> j) => BundleRecord(
    id: j['id'] as String,
    name: j['name'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    photo: base64Decode(j['photo'] as String),
    marks: (j['marks'] as List)
        .map((m) => BarMark.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
    diameter: (j['diameter'] as num).toDouble(),
    length: (j['length'] as num).toDouble(),
    reviewed: j['reviewed'] == true,
    sample: j['sample'] == true,
  );
}

String recordsCsv(List<BundleRecord> records) {
  String cell(String value) {
    // Prevent spreadsheet formula execution for user-entered names.
    final safe = RegExp(r'^\s*[=+@\-\t\r]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  return '\uFEFFBundle,Date,Bars,Diameter (mm),Length (m),Estimated weight (kg),Reviewed,Sample\r\n${records.map((r) => [cell(r.name), cell(r.createdAt.toIso8601String()), r.marks.length, r.diameter, r.length, r.weightKg.toStringAsFixed(2), r.reviewed, r.sample].join(',')).join('\r\n')}\r\n';
}
