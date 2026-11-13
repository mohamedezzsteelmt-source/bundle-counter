import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'detector.dart';
import 'models.dart';
import 'main.dart' show ink, olive, lime, muted;

enum EditTool { move, add, remove }

class CountEditor extends StatefulWidget {
  const CountEditor({
    super.key,
    required this.photo,
    required this.onSave,
    this.existing,
    this.sample = false,
  });
  final Uint8List photo;
  final BundleRecord? existing;
  final bool sample;
  final Future<void> Function(BundleRecord) onSave;
  @override
  State<CountEditor> createState() => _CountEditorState();
}

class _CountEditorState extends State<CountEditor> {
  List<BarMark> marks = [];
  final List<List<BarMark>> undoStack = [];
  final transform = TransformationController();
  final name = TextEditingController(),
      diameter = TextEditingController(),
      length = TextEditingController();
  final formKey = GlobalKey<FormState>();
  EditTool tool = EditTool.add;
  double aspect = 1, radius = 0.025, sensitivity = 0.45;
  bool detecting = false,
      saving = false,
      reviewed = false,
      dirty = false,
      allowPop = false,
      showNumbers = true;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    marks = List.of(old?.marks ?? []);
    reviewed = old?.reviewed ?? false;
    radius = widget.sample ? 0.05 : 0.025;
    name.text =
        old?.name ??
        (widget.sample
            ? 'Practice bundle'
            : 'Bundle ${DateTime.now().day}-${DateTime.now().month}');
    diameter.text = (old?.diameter ?? 16).toStringAsFixed(0);
    length.text = (old?.length ?? 12).toString();
    for (final controller in [name, diameter, length]) {
      controller.addListener(changed);
    }
    getDimensions();
  }

  void changed() {
    if (mounted) setState(() => dirty = true);
  }

  Future<void> getDimensions() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.photo);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) {
        setState(() {
          aspect = ratio;
          ready = true;
        });
      }
    } catch (_) {
      message('Could not display this photo. Return and choose another image.');
    }
  }

  @override
  void dispose() {
    transform.dispose();
    name.dispose();
    diameter.dispose();
    length.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void snapshot() {
    undoStack.add(List.of(marks));
    if (undoStack.length > 50) undoStack.removeAt(0);
    reviewed = false;
    dirty = true;
  }

  void undo() {
    if (undoStack.isEmpty) return;
    setState(() {
      marks = undoStack.removeLast();
      reviewed = false;
      dirty = true;
    });
  }

  void tap(Offset position, Size size) {
    if (detecting || saving || tool == EditTool.move) return;
    final p = Offset(
      (position.dx / size.width).clamp(0, 1),
      (position.dy / size.height).clamp(0, 1),
    );
    if (tool == EditTool.add) {
      // Avoid an accidental duplicate tap at the same end.
      final minSide = math.min(size.width, size.height);
      if (marks.any(
        (m) =>
            ((Offset(m.x * size.width, m.y * size.height) - position).distance <
            math.max(5, m.radius * minSide * 0.5)),
      )) {
        return;
      }
      setState(() {
        snapshot();
        marks.add(BarMark(p.dx, p.dy, radius));
      });
    } else {
      var nearest = -1;
      var distance = double.infinity;
      for (var i = 0; i < marks.length; i++) {
        final d =
            (Offset(marks[i].x * size.width, marks[i].y * size.height) -
                    position)
                .distance;
        if (d < distance) {
          distance = d;
          nearest = i;
        }
      }
      if (nearest >= 0 &&
          distance <
              math.max(
                14,
                marks[nearest].radius * math.min(size.width, size.height) * 1.5,
              )) {
        setState(() {
          snapshot();
          marks.removeAt(nearest);
        });
      }
    }
  }

  Future<bool> confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> suggest() async {
    if (detecting || saving) return;
    if (marks.isNotEmpty &&
        !await confirm(
          'Replace current markers?',
          'Suggestions will replace your current markers. You can undo this change.',
          'Replace',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => detecting = true);
    try {
      final detected = await compute(
        detectBars,
        DetectionRequest(widget.photo, radius, sensitivity),
      );
      if (mounted) {
        setState(() {
          snapshot();
          marks = detected;
        });
        message(
          '${detected.length} suggestions. Check every marker and correct missed or extra bars.',
        );
      }
    } catch (_) {
      message(
        'Suggestions could not be generated. You can still tap to count manually.',
      );
    } finally {
      if (mounted) setState(() => detecting = false);
    }
  }

  Future<void> leave() async {
    if (saving || detecting) return;
    if (dirty &&
        !await confirm(
          'Discard unsaved changes?',
          'Your changes to this bundle have not been saved.',
          'Discard',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> save() async {
    if (saving || detecting) return;
    if (!formKey.currentState!.validate()) return;
    if (marks.isEmpty) {
      message('Add at least one bar marker before saving.');
      return;
    }
    setState(() => saving = true);
    final now = DateTime.now();
    final record = BundleRecord(
      id: widget.existing?.id ?? now.microsecondsSinceEpoch.toString(),
      name: name.text.trim(),
      createdAt: widget.existing?.createdAt ?? now,
      photo: widget.photo,
      marks: List.of(marks),
      diameter: parse(diameter.text)!,
      length: parse(length.text)!,
      reviewed: reviewed,
      sample: widget.sample,
    );
    try {
      await widget.onSave(record);
      if (!mounted) return;
      setState(() {
        dirty = false;
        allowPop = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, record);
    } catch (_) {
      message(
        'Could not save. Your edits are still here; free some storage and try again.',
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  double? parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));
  String? numberValidator(String? text, double min, double max) {
    final n = parse(text ?? '');
    return n == null || !n.isFinite || n < min || n > max
        ? 'Enter $min–$max'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final busy = detecting || saving;
    final d = parse(diameter.text) ?? 0, l = parse(length.text) ?? 0;
    final weight = marks.length * d * d / 162 * l;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: busy ? null : leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(
            'Review the count',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
          ),
          actions: [
            IconButton(
              tooltip: 'Undo last marker change',
              onPressed: busy || undoStack.isEmpty ? null : undo,
              icon: const Icon(Icons.undo),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Form(
                key: formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  children: [
                    if (widget.sample)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: lime,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'PRACTICE IMAGE · 37 illustrated bar ends',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${marks.length}',
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'bars marked',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                reviewed
                                    ? 'Reviewed by you'
                                    : 'Check each visible bar end',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: reviewed ? lime : const Color(0xFFF2E5CE),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            reviewed ? 'REVIEWED' : 'REVIEW',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final height = math.min(
                          420.0,
                          constraints.maxWidth / aspect,
                        );
                        final width = height * aspect;
                        return Container(
                          height: height,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: SizedBox(
                                  width: width,
                                  height: height,
                                  child: InteractiveViewer(
                                    transformationController: transform,
                                    minScale: 1,
                                    maxScale: 8,
                                    panEnabled: tool == EditTool.move,
                                    scaleEnabled: tool == EditTool.move,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (details) => tap(
                                        details.localPosition,
                                        Size(width, height),
                                      ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.memory(
                                            widget.photo,
                                            fit: BoxFit.fill,
                                          ),
                                          CustomPaint(
                                            painter: MarksPainter(
                                              marks,
                                              showNumbers,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 10,
                                top: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ink.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tool == EditTool.move
                                        ? 'PINCH TO ZOOM · DRAG TO MOVE'
                                        : tool == EditTool.add
                                        ? 'TAP A BAR END TO ADD'
                                        : 'TAP A MARKER TO REMOVE',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              if (detecting)
                                const Positioned.fill(
                                  child: ColoredBox(
                                    color: Color(0xAA202A26),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(
                                            color: lime,
                                          ),
                                          SizedBox(height: 14),
                                          Text(
                                            'Finding circular ends…',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<EditTool>(
                      segments: const [
                        ButtonSegment(
                          value: EditTool.move,
                          icon: Icon(Icons.pan_tool_outlined, size: 18),
                          label: Text('Move'),
                        ),
                        ButtonSegment(
                          value: EditTool.add,
                          icon: Icon(Icons.add_circle_outline, size: 18),
                          label: Text('Add'),
                        ),
                        ButtonSegment(
                          value: EditTool.remove,
                          icon: Icon(Icons.remove_circle_outline, size: 18),
                          label: Text('Remove'),
                        ),
                      ],
                      selected: {tool},
                      onSelectionChanged: busy
                          ? null
                          : (v) => setState(() => tool = v.first),
                      showSelectedIcon: false,
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => showNumbers = !showNumbers),
                          icon: Icon(
                            showNumbers
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 17,
                          ),
                          label: const Text('Numbers'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => transform.value = Matrix4.identity(),
                          child: const Text('Reset zoom'),
                        ),
                      ],
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ExpansionTile(
                        initiallyExpanded: widget.existing == null,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: const Text(
                          'Automatic suggestions',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Experimental · always review',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Match this circle to an average bar end. The detector searches a range of sizes around it.',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                LayoutBuilder(
                                  builder: (context, c) {
                                    final displayWidth =
                                        MediaQuery.sizeOf(
                                          context,
                                        ).width.clamp(0, 800) -
                                        36;
                                    final displayHeight = math.min(
                                      420.0,
                                      displayWidth / aspect,
                                    );
                                    final short = math.min(
                                      displayHeight * aspect,
                                      displayHeight,
                                    );
                                    return Row(
                                      children: [
                                        SizedBox(
                                          width: 60,
                                          height: 52,
                                          child: Center(
                                            child: Container(
                                              width: radius * short * 2,
                                              height: radius * short * 2,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: olive,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: radius,
                                            min: 0.008,
                                            max: 0.10,
                                            divisions: 92,
                                            label:
                                                '${(radius * 200).toStringAsFixed(1)}% diameter',
                                            onChanged: busy
                                                ? null
                                                : (v) => setState(
                                                    () => radius = v,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                Row(
                                  children: [
                                    const Text(
                                      'Sensitivity',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: sensitivity,
                                        min: 0,
                                        max: 1,
                                        divisions: 10,
                                        label: sensitivity < 0.4
                                            ? 'Fewer'
                                            : sensitivity > 0.7
                                            ? 'More'
                                            : 'Balanced',
                                        onChanged: busy
                                            ? null
                                            : (v) => setState(
                                                () => sensitivity = v,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: busy || !ready ? null : suggest,
                                    icon: const Icon(
                                      Icons.auto_fix_high_outlined,
                                      size: 20,
                                    ),
                                    label: Text(
                                      detecting
                                          ? 'Finding bars…'
                                          : 'Suggest bars',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'For photos with several bundles, crop to the bundle you want before importing. Check every marker and use Add and Remove to correct the result.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Bundle details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: name,
                      enabled: !busy,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Bundle name',
                        counterText: '',
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Enter a bundle name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: diameter,
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Diameter',
                              suffixText: 'mm',
                            ),
                            validator: (v) => numberValidator(v, 4, 80),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: length,
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Bar length',
                              suffixText: 'm',
                            ),
                            validator: (v) => numberValidator(v, 0.1, 30),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EDDF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.scale_outlined,
                            size: 21,
                            color: olive,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Estimated bundle weight',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${weight.isFinite && d >= 4 && d <= 80 && l >= 0.1 && l <= 30 ? weight.toStringAsFixed(1) : '—'} kg',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: reviewed,
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              reviewed = v ?? false;
                              dirty = true;
                            }),
                      title: const Text(
                        'I checked every visible bar end',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Unchecked counts are saved as needs review.',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : save,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(saving ? 'Saving…' : 'Save bundle'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A photo cannot account for hidden bar ends.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarksPainter extends CustomPainter {
  const MarksPainter(this.marks, this.showNumbers);
  final List<BarMark> marks;
  final bool showNumbers;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i],
          center = Offset(mark.x * size.width, mark.y * size.height);
      final radius = math.max(
        4.0,
        mark.radius * math.min(size.width, size.height),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = lime.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = lime
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      if (showNumbers) {
        final text = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: Colors.white,
              fontSize: math.max(8, math.min(12, radius)),
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      } else {
        canvas.drawCircle(center, 2, Paint()..color = lime);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MarksPainter oldDelegate) => true;
}
