import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Normalized coordinates survive image resizing and zooming.
class BarMark {
  const BarMark(this.x, this.y, this.radius);
  final double x, y, radius;
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'r': radius};
  factory BarMark.fromJson(Map<String, dynamic> j) => BarMark(
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['r'] as num).toDouble(),
  );
}

class DetectionRequest {
  const DetectionRequest(this.bytes, this.radiusFraction, this.sensitivity);
  final Uint8List bytes;

  /// Radius as a fraction of the shorter image side.
  final double radiusFraction, sensitivity;
}

/// Experimental, offline gradient-circle detector. No learned model or server.
/// Assumes visible, approximately circular ends of similar size.
List<BarMark> detectBars(DetectionRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('This photo could not be decoded.');
  }
  final oriented = img.bakeOrientation(decoded);
  final scale = 640 / math.max(oriented.width, oriented.height);
  final picture = scale < 1
      ? img.copyResize(
          oriented,
          width: (oriented.width * scale).round(),
          height: (oriented.height * scale).round(),
        )
      : oriented;
  final blurred = img.gaussianBlur(picture, radius: 1);
  final w = blurred.width, h = blurred.height;
  final gray = Float32List(w * h);
  for (final p in blurred) {
    gray[p.y * w + p.x] = p.luminance.toDouble();
  }
  final gx = Float32List(w * h), gy = Float32List(w * h);
  final magnitude = Float32List(w * h);
  final edges = <int>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final dx =
          -gray[i - w - 1] +
          gray[i - w + 1] -
          2 * gray[i - 1] +
          2 * gray[i + 1] -
          gray[i + w - 1] +
          gray[i + w + 1];
      final dy =
          -gray[i - w - 1] -
          2 * gray[i - w] -
          gray[i - w + 1] +
          gray[i + w - 1] +
          2 * gray[i + w] +
          gray[i + w + 1];
      final m = math.sqrt(dx * dx + dy * dy);
      magnitude[i] = m;
      if (m > 65 - request.sensitivity * 30) {
        gx[i] = dx / m;
        gy[i] = dy / m;
        edges.add(i);
      }
    }
  }
  final expected = (math.min(w, h) * request.radiusFraction).clamp(4.0, 100.0);
  final candidates = <({double x, double y, double r, double score})>[];
  for (final factor in [0.72, 0.82, 0.91, 1.0, 1.09, 1.18, 1.28]) {
    final r = expected * factor;
    final votes = Float32List(w * h);
    for (final i in edges) {
      final x = i % w, y = i ~/ w;
      for (final direction in [-1, 1]) {
        final cx = (x + direction * gx[i] * r).round();
        final cy = (y + direction * gy[i] * r).round();
        if (cx > 1 && cx < w - 2 && cy > 1 && cy < h - 2) {
          // A 3x3 vote neighborhood tolerates edge and radius quantization.
          for (var yy = cy - 1; yy <= cy + 1; yy++) {
            for (var xx = cx - 1; xx <= cx + 1; xx++) {
              votes[yy * w + xx] += 1;
            }
          }
        }
      }
    }
    final border = r.ceil() + 2;
    for (var y = border; y < h - border; y++) {
      for (var x = border; x < w - border; x++) {
        final i = y * w + x, v = votes[i];
        if (v < math.max(8, r * (1.4 - request.sensitivity * 0.5))) continue;
        if (v < votes[i - 1] ||
            v <= votes[i + 1] ||
            v < votes[i - w] ||
            v <= votes[i + w]) {
          continue;
        }
        var supported = 0;
        for (var k = 0; k < 32; k++) {
          final angle = k * math.pi / 16,
              ux = math.cos(angle),
              uy = math.sin(angle);
          var best = 0.0;
          for (final dr in [-1.5, 0.0, 1.5]) {
            final ix = (x + (r + dr) * ux).round(),
                iy = (y + (r + dr) * uy).round();
            if (ix < 0 || ix >= w || iy < 0 || iy >= h) continue;
            final index = iy * w + ix;
            final alignment = (gx[index] * ux + gy[index] * uy).abs();
            if (magnitude[index] > 40 && alignment > best) best = alignment;
          }
          if (best > 0.70) supported++;
        }
        if (supported >= 25 - (request.sensitivity * 8).round()) {
          candidates.add((
            x: x.toDouble(),
            y: y.toDouble(),
            r: r,
            score: supported + v / (r * 5),
          ));
        }
      }
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final kept = <({double x, double y, double r, double score})>[];
  for (final c in candidates) {
    if (kept.every(
      (p) =>
          math.pow(c.x - p.x, 2) + math.pow(c.y - p.y, 2) >
          math.pow(math.min(c.r, p.r) * 1.5, 2),
    )) {
      kept.add(c);
      if (kept.length >= 1500) break;
    }
  }
  kept.sort(
    (a, b) => a.y.compareTo(b.y) == 0 ? a.x.compareTo(b.x) : a.y.compareTo(b.y),
  );
  return kept
      .map((c) => BarMark(c.x / w, c.y / h, c.r / math.min(w, h)))
      .toList();
}

Uint8List preparePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Use a JPEG or PNG photo.');
  if (decoded.width * decoded.height > 50000000) {
    throw const FormatException('Choose a photo smaller than 50 megapixels.');
  }
  final oriented = img.bakeOrientation(decoded);
  final ratio = 1600 / math.max(oriented.width, oriented.height);
  final resized = ratio < 1
      ? img.copyResize(
          oriented,
          width: (oriented.width * ratio).round(),
          height: (oriented.height * ratio).round(),
        )
      : oriented;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}
