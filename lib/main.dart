import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'detector.dart';
import 'models.dart';
import 'storage.dart';
import 'editor.dart';

const ink = Color(0xFF202A26);
const olive = Color(0xFF526B36);
const lime = Color(0xFFDAEDAA);
const paper = Color(0xFFF5F5EF);
const muted = Color(0xFF727970);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RebarApp());
}

class RebarApp extends StatelessWidget {
  const RebarApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ERM Final Bundle Bar Counter',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: olive,
        primary: olive,
        surface: paper,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        centerTitle: false,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          foregroundColor: ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final storage = RecordStorage();
  List<BundleRecord> records = [];
  bool loading = true, importing = false;
  String? storageError;
  int tab = 0;
  String query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final loaded = await storage.load();
      if (mounted) {
        setState(() {
          records = loaded;
          loading = false;
          storageError = null;
        });
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          await recoverPhoto();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          storageError =
              'Saved counts could not be read. Retry before making changes.';
        });
      }
    }
  }

  Future<void> recoverPhoto() async {
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.isEmpty) return;
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        final file = files.first;
        if (await file.length() > 30 * 1024 * 1024) {
          message(
            'The recovered photo is too large. Choose one smaller than 30 MB.',
          );
          return;
        }
        final bytes = await compute(preparePhoto, await file.readAsBytes());
        if (mounted) await openEditor(bytes);
      } else {
        message(
          'The previous photo could not be recovered. Please select it again.',
        );
      }
    } catch (_) {
      message(
        'The previous photo could not be recovered. Please select it again.',
      );
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> openEditor(
    Uint8List bytes, {
    BundleRecord? record,
    bool sample = false,
  }) async {
    if (storageError != null) {
      message(storageError!);
      return;
    }
    final result = await Navigator.of(context).push<BundleRecord>(
      MaterialPageRoute(
        builder: (_) => CountEditor(
          photo: bytes,
          existing: record,
          sample: sample,
          onSave: (updated) async {
            final next = [updated, ...records.where((r) => r.id != updated.id)];
            await storage.save(next);
            if (mounted) setState(() => records = next);
          },
        ),
      ),
    );
    if (result != null) message('Bundle saved on this device.');
  }

  Future<void> pick(ImageSource source) async {
    if (importing) return;
    setState(() => importing = true);
    Uint8List? prepared;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (file != null) {
        if (await file.length() > 30 * 1024 * 1024) {
          throw const FormatException('Choose a photo smaller than 30 MB.');
        }
        prepared = await compute(preparePhoto, await file.readAsBytes());
      }
    } catch (e) {
      message(
        e is FormatException
            ? e.message
            : 'Unable to open the image. Choose a JPEG or PNG file and try again.',
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
    if (prepared != null && mounted) await openEditor(prepared);
  }

  Future<void> sample() async {
    setState(() => importing = true);
    try {
      final photo = await makeSample();
      if (mounted) await openEditor(photo, sample: true);
    } catch (_) {
      message('The sample could not be opened. Please try again.');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> remove(BundleRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this bundle?'),
        content: Text(
          '“${record.name}” and its photo will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final next = records.where((r) => r.id != record.id).toList();
      await storage.save(next);
      if (mounted) setState(() => records = next);
    } catch (_) {
      message('Could not delete the bundle. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final actual = records.where((r) => !r.sample).toList();
    final total = actual.fold<int>(0, (sum, r) => sum + r.marks.length);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.grain_rounded, color: lime),
            ),
            const SizedBox(width: 10),
            const Text(
              'ERM Final Bundle Bar Counter',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE6EBDC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.offline_bolt_outlined, size: 14, color: olive),
                  SizedBox(width: 4),
                  Text(
                    'OFFLINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: olive,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : storageError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(storageError!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : tab == 0
                ? home(total, actual.length)
                : tab == 1
                ? history()
                : guide(),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: lime,
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.center_focus_strong_outlined),
            selectedIcon: Icon(Icons.center_focus_strong),
            label: 'Count',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Bundles',
          ),
          NavigationDestination(
            icon: Icon(Icons.help_outline_rounded),
            selectedIcon: Icon(Icons.help_rounded),
            label: 'Guide',
          ),
        ],
      ),
    );
  }

  Widget home(int total, int bundles) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
    children: [
      const Text(
        'ON-SITE. ON THE COUNT.',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: muted,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Every bar counts.',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Turn a bundle photo into a count you can check.',
        style: TextStyle(color: muted, fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 24),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -25,
              child: Opacity(
                opacity: 0.25,
                child: CustomPaint(
                  size: const Size(220, 220),
                  painter: BundlePattern(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.filter_center_focus_rounded,
                    color: lime,
                    size: 28,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'One bundle.\nOne clear count.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Open a bundle photo, mark the bars,\nand save your result.',
                    style: TextStyle(color: Color(0xFFBFC9BF), height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: importing
                          ? null
                          : () => pick(ImageSource.gallery),
                      style: FilledButton.styleFrom(
                        backgroundColor: lime,
                        foregroundColor: ink,
                      ),
                      icon: importing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined, size: 21),
                      label: Text(
                        importing ? 'Opening photo…' : 'Open a bundle photo',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: importing ? null : () => pick(ImageSource.gallery),
        icon: const Icon(Icons.photo_library_outlined, size: 20),
        label: const Text('Import a photo'),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: stat(
              '$bundles',
              'SAVED BUNDLES',
              Icons.inventory_2_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: stat(
              NumberFormat.decimalPattern().format(total),
              'BARS MARKED',
              Icons.grain,
            ),
          ),
        ],
      ),
      const SizedBox(height: 26),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Recent bundles',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          TextButton(
            onPressed: () => setState(() => tab = 1),
            child: const Text('View all →'),
          ),
        ],
      ),
      if (records.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'Your first count starts here.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try the illustrated 37-bar sample to learn the tools.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.4),
              ),
              TextButton.icon(
                onPressed: importing ? null : sample,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('Try a sample'),
              ),
            ],
          ),
        )
      else
        ...records.take(3).map(recordTile),
      const SizedBox(height: 18),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 13, color: muted),
          SizedBox(width: 6),
          Text(
            'Photos and counts stay on this device.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    ],
  );
  Widget stat(String value, String label, IconData icon) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E8DF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            Icon(icon, color: olive, size: 20),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            letterSpacing: 1.2,
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
  Widget recordTile(BundleRecord r) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openEditor(r.photo, record: r, sample: r.sample),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  r.photo,
                  width: 56,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('d MMM').format(r.createdAt.toLocal())} · Ø${r.diameter.toStringAsFixed(0)} mm',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.sample
                          ? 'SAMPLE'
                          : r.reviewed
                          ? 'REVIEWED'
                          : 'NEEDS REVIEW',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: r.reviewed ? olive : const Color(0xFF976B2D),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    '${r.marks.length}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'bars',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'Bundle options',
                onSelected: (v) {
                  if (v == 'delete') {
                    remove(r);
                  } else {
                    shareRecords(context, [r]);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'share', child: Text('Export CSV')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget history() {
    final visible = records
        .where((r) => r.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your bundles',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Export all bundles as CSV',
              onPressed: records.isEmpty
                  ? null
                  : () => shareRecords(context, records),
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'A record of every count, ready when you need it.',
          style: TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            hintText: 'Find a bundle',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 22),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              records.isEmpty
                  ? 'No saved bundles yet. Start a count from the Count tab.'
                  : 'No bundles match your search.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
            ),
          ),
        ...visible.map(recordTile),
      ],
    );
  }

  Widget guide() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'A better photo.\nA better count.',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 24),
      tip(
        '01',
        'Face the cut ends',
        'Stand directly in front of the bundle. Include every bar end and avoid angled shots.',
        Icons.center_focus_strong,
      ),
      tip(
        '02',
        'Find even light',
        'Use sharp, well-lit photos. Shadows, rust, straps, and overlapping ends can confuse suggestions.',
        Icons.wb_sunny_outlined,
      ),
      tip(
        '03',
        'Match the circle size',
        'In the review screen, match the reference circle to a typical bar end, then run Suggest bars. Suggestions use an experimental circle detector.',
        Icons.radio_button_unchecked,
      ),
      tip(
        '04',
        'Check every marker',
        'Tap to add missing bars or remove extras. Use Move to zoom and pan, then switch back to Add or Remove. Verify every visible bar before saving as reviewed.',
        Icons.touch_app_outlined,
      ),
      tip(
        '05',
        'Keep a useful record',
        'Add the bundle name, diameter, and length. Weight is an estimate using count × diameter² ÷ 162 × length (mm and m).',
        Icons.inventory_2_outlined,
      ),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFE7ECDd),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Automatic suggestions are not a certified inventory count. Hidden ends cannot be counted from a photo. Review before using a result for a delivery or purchase.',
          style: TextStyle(height: 1.5, color: ink),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        'Privacy',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'No account or image upload is needed. Photos and counts are saved locally. CSV export shares count metadata through your device’s share sheet. Removing the app may remove your saved records.',
        style: TextStyle(color: muted, height: 1.5),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: importing ? null : sample,
        icon: const Icon(Icons.play_circle_outline),
        label: const Text('Practice with the sample'),
      ),
      const SizedBox(height: 20),
      const Text(
        'ERM FINAL BUNDLE BAR COUNTER  /  1.0',
        style: TextStyle(color: muted, fontSize: 10, letterSpacing: 2),
      ),
    ],
  );
  Widget tip(String n, String title, String body, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: olive),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$n  /  $title',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(color: muted, height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> shareRecords(
  BuildContext context,
  List<BundleRecord> records,
) async {
  try {
    final box = context.findRenderObject() as RenderBox?;
    final bytes = Uint8List.fromList(
      const Utf8Encoder().convert(recordsCsv(records)),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/csv')],
        fileNameOverrides: ['rebar-counts.csv'],
        title: 'Rebar bundle counts',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed. Please try again.')),
      );
    }
  }
}

class BundlePattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 5; col++) {
        final center = Offset(col * 42.0 + (row.isOdd ? 21 : 0), row * 36.0);
        canvas.drawCircle(center, 18, paint);
        canvas.drawCircle(center, 13, paint..strokeWidth = 0.7);
        paint.strokeWidth = 2;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Deliberately illustrated practice image, not a validation photograph.
Future<Uint8List> makeSample() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 700, 600),
    Paint()..color = const Color(0xFF29312F),
  );
  final random = math.Random(7);
  for (var i = 0; i < 2000; i++) {
    final shade = 45 + random.nextInt(18);
    canvas.drawCircle(
      Offset(random.nextDouble() * 700, random.nextDouble() * 600),
      random.nextDouble() * 2,
      Paint()..color = Color.fromARGB(255, shade, shade + 5, shade + 3),
    );
  }
  for (var row = 0; row < 7; row++) {
    final count = 7 - (3 - row).abs();
    for (var col = 0; col < count; col++) {
      final center = Offset(
        350 + (col - (count - 1) / 2) * 76,
        90 + row * 70.0,
      );
      canvas.drawCircle(
        center + const Offset(3, 5),
        34,
        Paint()..color = const Color(0xFF111916),
      );
      canvas.drawCircle(center, 30, Paint()..color = const Color(0xFFB2B4AC));
      canvas.drawCircle(
        center,
        27,
        Paint()
          ..shader = ui.Gradient.linear(
            center - const Offset(20, 20),
            center + const Offset(20, 20),
            [const Color(0xFF989F98), const Color(0xFF616D68)],
          ),
      );
      for (var j = 0; j < 32; j++) {
        final a = random.nextDouble() * math.pi * 2,
            r = random.nextDouble() * 24;
        canvas.drawCircle(
          center + Offset(math.cos(a) * r, math.sin(a) * r),
          0.6,
          Paint()..color = const Color(0xFFB4BAB2),
        );
      }
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(700, 600);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}
