import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diabetes_app/services/ratio_schedule_resolver.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Editable pump-style ratio bands (FSI or I:C).
class RatioScheduleEditor extends StatefulWidget {
  const RatioScheduleEditor({
    super.key,
    required this.label,
    required this.helperText,
    required this.valueHint,
    required this.initial,
    required this.onChanged,
    this.maxSegments = RatioScheduleResolver.maxSegments,
  });

  final String label;
  final String helperText;
  final String valueHint;
  final List<RatioSegment> initial;
  final ValueChanged<List<RatioSegment>> onChanged;
  final int maxSegments;

  @override
  State<RatioScheduleEditor> createState() => RatioScheduleEditorState();
}

class RatioScheduleEditorState extends State<RatioScheduleEditor> {
  late List<_Row> _rows;
  final _resolver = const RatioScheduleResolver();

  @override
  void initState() {
    super.initState();
    _rows = _fromSegments(widget.initial);
    if (_rows.isEmpty) {
      _rows = [_Row(startMinute: 0, valueText: '')];
    }
  }

  @override
  void didUpdateWidget(covariant RatioScheduleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-seed when parent reloads a different schedule identity.
    if (!_sameSchedule(oldWidget.initial, widget.initial)) {
      for (final r in _rows) {
        r.dispose();
      }
      _rows = _fromSegments(widget.initial);
      if (_rows.isEmpty) {
        _rows = [_Row(startMinute: 0, valueText: '')];
      }
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  bool _sameSchedule(List<RatioSegment> a, List<RatioSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<_Row> _fromSegments(List<RatioSegment> segments) {
    final normalized = _resolver.normalize(segments);
    return [
      for (final s in normalized)
        _Row(
          startMinute: s.startMinute,
          valueText: s.value > 0 ? formatWhole(s.value) : '',
        ),
    ];
  }

  List<RatioSegment> currentSegments() {
    final out = <RatioSegment>[];
    for (final r in _rows) {
      final raw = r.controller.text.trim().replaceAll(',', '.');
      final value = double.tryParse(raw);
      if (value == null || value <= 0) continue;
      out.add(RatioSegment(startMinute: r.startMinute, value: value));
    }
    return _resolver.normalize(out);
  }

  /// Validate and notify parent. Returns error message or null.
  String? validateAndEmit() {
    final segments = <RatioSegment>[];
    for (final r in _rows) {
      final raw = r.controller.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) {
        return '${widget.label}: preencha todos os valores.';
      }
      final value = double.tryParse(raw);
      if (value == null || value <= 0) {
        return '${widget.label}: valor deve ser positivo.';
      }
      segments.add(RatioSegment(startMinute: r.startMinute, value: value));
    }
    final normalized = _resolver.normalize(segments);
    final err = _resolver.validate(normalized, label: widget.label);
    if (err != null) return err;
    widget.onChanged(normalized);
    return null;
  }

  void _emit() {
    widget.onChanged(currentSegments());
  }

  Future<void> _pickStart(int index) async {
    final row = _rows[index];
    // Midnight band is fixed.
    if (row.startMinute == 0 &&
        _rows.where((r) => r.startMinute == 0).length == 1 &&
        index == _rows.indexWhere((r) => r.startMinute == 0)) {
      // Allow picking only if this isn't the sole midnight requirement —
      // keep start 0 immutable for the first midnight row.
      final isMidnightRow = row.startMinute == 0;
      if (isMidnightRow) return;
    }
    if (row.startMinute == 0) return;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (row.startMinute ~/ 60) % 24,
        minute: row.startMinute % 60,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    if (minute == 0) return;
    if (_rows.any((r) => r.startMinute == minute && !identical(r, row))) {
      return;
    }
    setState(() {
      row.startMinute = minute;
      _rows.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    });
    _emit();
  }

  Future<void> _addRow() async {
    if (_rows.length >= widget.maxSegments) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    if (_rows.any((r) => r.startMinute == minute)) return;
    setState(() {
      _rows.add(_Row(startMinute: minute, valueText: ''));
      _rows.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    });
    _emit();
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    final row = _rows[index];
    if (row.startMinute == 0) return;
    setState(() {
      row.dispose();
      _rows.removeAt(index);
    });
    _emit();
  }

  String _formatMinute(int minute) {
    final h = (minute ~/ 60) % 24;
    final m = minute % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
        SizedBox(height: 4),
        Text(
          widget.helperText,
          style: TextStyle(fontSize: 12, color: colors.muted, height: 1.35),
        ),
        SizedBox(height: 10),
        for (var i = 0; i < _rows.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: OutlinedButton(
                  onPressed: _rows[i].startMinute == 0
                      ? null
                      : () => _pickStart(i),
                  child: Text(_formatMinute(_rows[i].startMinute)),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _rows[i].controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: widget.valueHint,
                    isDense: true,
                  ),
                  onChanged: (_) => _emit(),
                  validator: (v) {
                    final raw = (v ?? '').trim().replaceAll(',', '.');
                    final n = double.tryParse(raw);
                    if (n == null || n <= 0) return 'Obrigatório';
                    return null;
                  },
                ),
              ),
              if (_rows[i].startMinute != 0)
                IconButton(
                  tooltip: 'Remover faixa',
                  onPressed: () => _removeRow(i),
                  icon: const Icon(Icons.close),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
          SizedBox(height: 8),
        ],
        if (_rows.length < widget.maxSegments)
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar faixa'),
              onPressed: _addRow,
            ),
          ),
      ],
    );
  }
}

class _Row {
  _Row({required this.startMinute, required String valueText})
      : controller = TextEditingController(text: valueText);

  int startMinute;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}
