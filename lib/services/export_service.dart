import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// CSV / text / PDF export for clinic visits.
class ExportService {
  const ExportService();

  static pw.ThemeData? _pdfThemeCache;

  Future<pw.ThemeData> _pdfTheme() async {
    final cached = _pdfThemeCache;
    if (cached != null) return cached;
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    return _pdfThemeCache = pw.ThemeData.withFont(base: base, bold: bold);
  }

  String buildCsv(
    List<Entry> entries, {
    List<BasalDose> basalDoses = const [],
  }) {
    final buf = StringBuffer();
    buf.writeln(
      'kind,recorded_at,glucose_mgdl,food_text,recommended_insulin_u,'
      'applied_insulin_u,carbs_g,basal_units,basal_insulin_name,notes',
    );

    final rows = <({DateTime at, String line})>[];
    for (final e in entries) {
      final carbs = _carbsFromEntry(e);
      rows.add((
        at: e.recordedAt,
        line: [
          'bolus',
          e.recordedAt.toUtc().toIso8601String(),
          e.glucoseMgdl,
          _csvEscape(e.foodText ?? ''),
          e.recommendedInsulin?.toString() ?? '',
          e.appliedInsulin?.toString() ?? '',
          carbs?.toString() ?? '',
          '',
          '',
          '',
        ].join(','),
      ));
    }
    for (final b in basalDoses) {
      rows.add((
        at: b.recordedAt,
        line: [
          'basal',
          b.recordedAt.toUtc().toIso8601String(),
          '',
          '',
          '',
          '',
          '',
          b.units.toString(),
          _csvEscape(b.insulinName ?? ''),
          _csvEscape(b.notes ?? ''),
        ].join(','),
      ));
    }
    rows.sort((a, b) => b.at.compareTo(a.at));
    for (final r in rows) {
      buf.writeln(r.line);
    }
    return buf.toString();
  }

  String buildTextReport({
    required Profile? profile,
    required List<Entry> entries,
    List<BasalDose> basalDoses = const [],
    HistoryStats? stats,
  }) {
    final computed = stats ?? HistoryStats.fromEntries(entries, profile: profile);
    final basalTotal =
        basalDoses.fold<double>(0, (sum, b) => sum + b.units);
    final buf = StringBuffer();
    buf.writeln('GlicoDose — relatório para consulta');
    buf.writeln('Gerado em: ${AppTime.formatDateTime(AppTime.now())}');
    buf.writeln('Fuso: ${profile?.timezone ?? AppTime.locationName}');
    buf.writeln('');
    if (profile != null) {
      buf.writeln('Paciente: ${profile.fullName ?? '—'}');
      buf.writeln(
        'Meta dia: ${profile.targetGlucoseMgdl ?? '—'} mg/dL · '
        'Meta noite: ${profile.targetNightMgdl ?? '—'} mg/dL',
      );
      buf.writeln(
        'FSI: ${profile.isfMgdlPerU ?? '—'} · I:C: ${profile.icRatio ?? '—'} · '
        'Insulina rápida: ${profile.rapidInsulinName ?? '—'} · '
        'Duração IOB: ${profile.insulinDurationHours} h · '
        'Passo: ${profile.doseStep} U',
      );
      if (profile.basalInsulinName != null || profile.basalDoseU != null) {
        buf.writeln(
          'Basal: ${profile.basalInsulinName ?? '—'} · '
          'Dose padrão: ${profile.basalDoseU != null ? formatWhole(profile.basalDoseU) : '—'} U',
        );
      }
      buf.writeln('');
    }
    buf.writeln('Resumo (${computed.count} bolus):');
    if (computed.avgGlucose != null) {
      buf.writeln(
        '  Glicose média: ${formatWhole(computed.avgGlucose)} mg/dL '
        '(${computed.minGlucose}–${computed.maxGlucose})',
      );
    }
    if (computed.tirPercent != null) {
      buf.writeln(
        '  TIR 70–180: ${computed.tirPercent!.round()}% '
        '(${computed.tirCount}/${computed.count})',
      );
    }
    if (computed.gmiPercent != null) {
      buf.writeln(
        '  GMI (eA1c estimado): ${computed.gmiPercent!.toStringAsFixed(1)}%',
      );
    }
    if (computed.inTargetPercent != null) {
      buf.writeln(
        '  Na meta pessoal (±20%): ${computed.inTargetPercent!.round()}%',
      );
    }
    buf.writeln(
      '  Insulina rápida aplicada: ${formatWhole(computed.totalAppliedU)} U',
    );
    buf.writeln(
      '  Basal aplicada: ${formatWhole(basalTotal)} U '
      '(${basalDoses.length} registro${basalDoses.length == 1 ? '' : 's'})',
    );
    buf.writeln('');
    buf.writeln('Registros:');
    buf.writeln('─' * 40);

    final timeline = <({DateTime at, void Function(StringBuffer) write})>[];
    for (final e in entries) {
      timeline.add((
        at: e.recordedAt,
        write: (b) {
          final carbs = _carbsFromEntry(e);
          b.writeln(AppTime.formatDateTime(e.recordedAt));
          b.writeln('  [Bolus] Glicemia: ${e.glucoseMgdl} mg/dL');
          if (e.foodText != null && e.foodText!.trim().isNotEmpty) {
            b.writeln('  Comida: ${e.foodText}');
          }
          if (carbs != null) {
            b.writeln('  Carbs: ${formatWhole(carbs)} g');
          }
          b.writeln(
            '  Insulina rec/apl: '
            '${formatWhole(e.recommendedInsulin ?? 0)} / '
            '${e.appliedInsulin != null ? formatWhole(e.appliedInsulin!) : '—'} U',
          );
          b.writeln('');
        },
      ));
    }
    for (final dose in basalDoses) {
      timeline.add((
        at: dose.recordedAt,
        write: (b) {
          b.writeln(AppTime.formatDateTime(dose.recordedAt));
          b.writeln(
            '  [Basal] ${formatWhole(dose.units)} U'
            '${dose.insulinName != null && dose.insulinName!.trim().isNotEmpty ? ' · ${dose.insulinName}' : ''}',
          );
          if (dose.notes != null && dose.notes!.trim().isNotEmpty) {
            b.writeln('  Notas: ${dose.notes}');
          }
          b.writeln('');
        },
      ));
    }
    timeline.sort((a, b) => b.at.compareTo(a.at));
    for (final item in timeline) {
      item.write(buf);
    }

    buf.writeln(
      'Ferramenta de apoio — não substitui orientação médica.',
    );
    return buf.toString();
  }

  Future<void> shareCsv(
    List<Entry> entries, {
    List<BasalDose> basalDoses = const [],
  }) async {
    final csv = buildCsv(entries, basalDoses: basalDoses);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/glicodose_historico_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Histórico GlicoDose (CSV)',
      ),
    );
  }

  Future<void> sharePdfLikeReport({
    required Profile? profile,
    required List<Entry> entries,
    List<BasalDose> basalDoses = const [],
  }) async {
    final stats = HistoryStats.fromEntries(entries, profile: profile);
    final text = buildTextReport(
      profile: profile,
      entries: entries,
      basalDoses: basalDoses,
      stats: stats,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/glicodose_relatorio_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await file.writeAsString(text, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Relatório GlicoDose',
        text: 'Relatório GlicoDose para consulta',
      ),
    );
  }

  /// Builds the clinic PDF bytes (also used by [sharePdfReport]).
  ///
  /// Embeds Noto Sans so Portuguese accents and punctuation render correctly
  /// (default Helvetica is Type1/Latin-1 only and warns under asserts).
  Future<List<int>> buildPdfBytes({
    required Profile? profile,
    required List<Entry> entries,
    List<BasalDose> basalDoses = const [],
  }) async {
    final stats = HistoryStats.fromEntries(entries, profile: profile);
    final basalTotal =
        basalDoses.fold<double>(0, (sum, b) => sum + b.units);
    final theme = await _pdfTheme();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'GlicoDose — relatório para consulta',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Gerado em: ${AppTime.formatDateTime(AppTime.now())} (${profile?.timezone ?? AppTime.locationName})',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          if (profile != null) ...[
            pw.Text('Paciente: ${profile.fullName ?? '—'}'),
            pw.Text(
              'Meta dia/noite: ${profile.targetGlucoseMgdl ?? '—'} / '
              '${profile.targetNightMgdl ?? '—'} mg/dL',
            ),
            pw.Text(
              'FSI ${profile.isfMgdlPerU ?? '—'} · I:C ${profile.icRatio ?? '—'} · '
              'Rápida ${profile.rapidInsulinName ?? '—'} · '
              'IOB ${profile.insulinDurationHours} h · passo ${profile.doseStep} U',
            ),
            if (profile.basalInsulinName != null || profile.basalDoseU != null)
              pw.Text(
                'Basal ${profile.basalInsulinName ?? '—'} · '
                'padrão ${formatWhole(profile.basalDoseU)} U',
              ),
            pw.SizedBox(height: 10),
          ],
          pw.Text(
            'Resumo (${stats.count} bolus · ${basalDoses.length} basal)',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (stats.avgGlucose != null)
            pw.Text(
              'Glicose média: ${formatWhole(stats.avgGlucose)} mg/dL '
              '(${stats.minGlucose}–${stats.maxGlucose})',
            ),
          if (stats.tirPercent != null)
            pw.Text(
              'TIR 70–180: ${stats.tirPercent!.round()}% '
              '(${stats.tirCount}/${stats.count})',
            ),
          if (stats.gmiPercent != null)
            pw.Text(
              'GMI (eA1c estimado): ${stats.gmiPercent!.toStringAsFixed(1)}%',
            ),
          if (stats.inTargetPercent != null)
            pw.Text(
              'Na meta pessoal (±20%): ${stats.inTargetPercent!.round()}%',
            ),
          pw.Text(
            'Insulina rápida aplicada: ${formatWhole(stats.totalAppliedU)} U',
          ),
          pw.Text(
            'Basal aplicada: ${formatWhole(basalTotal)} U',
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Registros',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          ..._pdfTimeline(entries, basalDoses),
          pw.SizedBox(height: 16),
          pw.Text(
            'Ferramenta de apoio — não substitui orientação médica.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> sharePdfReport({
    required Profile? profile,
    required List<Entry> entries,
    List<BasalDose> basalDoses = const [],
  }) async {
    final bytes = await buildPdfBytes(
      profile: profile,
      entries: entries,
      basalDoses: basalDoses,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/glicodose_relatorio_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Relatório GlicoDose (PDF)',
        text: 'Relatório PDF GlicoDose para consulta',
      ),
    );
  }

  List<pw.Widget> _pdfTimeline(
    List<Entry> entries,
    List<BasalDose> basalDoses,
  ) {
    final items = <({DateTime at, pw.Widget widget})>[];
    for (final e in entries) {
      final carbs = _carbsFromEntry(e);
      items.add((
        at: e.recordedAt,
        widget: pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${AppTime.formatDateTime(e.recordedAt)} · Bolus',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Glicemia: ${e.glucoseMgdl} mg/dL'),
              if (e.foodText != null && e.foodText!.trim().isNotEmpty)
                pw.Text('Comida: ${e.foodText}'),
              if (carbs != null) pw.Text('Carbs: ${formatWhole(carbs)} g'),
              pw.Text(
                'Insulina rec/apl: '
                '${formatWhole(e.recommendedInsulin ?? 0)} / '
                '${e.appliedInsulin != null ? formatWhole(e.appliedInsulin!) : '—'} U',
              ),
            ],
          ),
        ),
      ));
    }
    for (final b in basalDoses) {
      items.add((
        at: b.recordedAt,
        widget: pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${AppTime.formatDateTime(b.recordedAt)} · Basal',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                '${formatWhole(b.units)} U'
                '${b.insulinName != null && b.insulinName!.trim().isNotEmpty ? ' · ${b.insulinName}' : ''}',
              ),
            ],
          ),
        ),
      ));
    }
    items.sort((a, b) => b.at.compareTo(a.at));
    final take = items.take(80).map((e) => e.widget).toList();
    if (items.length > 80) {
      take.add(
        pw.Text(
          '… e mais ${items.length - 80} registros (use CSV para o histórico completo).',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }
    return take;
  }

  double? _carbsFromEntry(Entry e) {
    final raw = e.gptRawResponse;
    if (raw == null) return null;
    final v = raw['carboidratos_g'];
    if (v is num) return v.toDouble();
    return null;
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
