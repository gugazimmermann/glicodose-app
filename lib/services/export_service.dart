import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// CSV / text report export for clinic visits.
class ExportService {
  const ExportService();

  String buildCsv(List<Entry> entries) {
    final buf = StringBuffer();
    buf.writeln(
      'recorded_at,glucose_mgdl,food_text,recommended_insulin_u,applied_insulin_u,carbs_g',
    );
    for (final e in entries) {
      final carbs = _carbsFromEntry(e);
      buf.writeln(
        [
          e.recordedAt.toUtc().toIso8601String(),
          e.glucoseMgdl,
          _csvEscape(e.foodText ?? ''),
          e.recommendedInsulin?.toString() ?? '',
          e.appliedInsulin?.toString() ?? '',
          carbs?.toString() ?? '',
        ].join(','),
      );
    }
    return buf.toString();
  }

  String buildTextReport({
    required Profile? profile,
    required List<Entry> entries,
  }) {
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final buf = StringBuffer();
    buf.writeln('GlicoDose — relatório para consulta');
    buf.writeln('Gerado em: ${df.format(DateTime.now())}');
    buf.writeln('');
    if (profile != null) {
      buf.writeln('Paciente: ${profile.fullName ?? '—'}');
      buf.writeln(
        'Meta dia: ${profile.targetGlucoseMgdl ?? '—'} mg/dL · '
        'Meta noite: ${profile.targetNightMgdl ?? '—'} mg/dL',
      );
      buf.writeln(
        'FSI: ${profile.isfMgdlPerU ?? '—'} · I:C: ${profile.icRatio ?? '—'} · '
        'Insulina: ${profile.rapidInsulinName ?? '—'}',
      );
      buf.writeln('');
    }
    buf.writeln('Registros (${entries.length}):');
    buf.writeln('─' * 40);
    for (final e in entries) {
      final carbs = _carbsFromEntry(e);
      buf.writeln(df.format(e.recordedAt.toLocal()));
      buf.writeln('  Glicemia: ${e.glucoseMgdl} mg/dL');
      if (e.foodText != null && e.foodText!.trim().isNotEmpty) {
        buf.writeln('  Comida: ${e.foodText}');
      }
      if (carbs != null) {
        buf.writeln('  Carbs: ${formatWhole(carbs)} g');
      }
      buf.writeln(
        '  Insulina rec/apl: '
        '${formatWhole(e.recommendedInsulin ?? 0)} / '
        '${e.appliedInsulin != null ? formatWhole(e.appliedInsulin!) : '—'} U',
      );
      buf.writeln('');
    }
    buf.writeln(
      'Ferramenta de apoio — não substitui orientação médica.',
    );
    return buf.toString();
  }

  Future<void> shareCsv(List<Entry> entries) async {
    final csv = buildCsv(entries);
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
  }) async {
    // Text report shareable to print / save as PDF from the system sheet.
    final text = buildTextReport(profile: profile, entries: entries);
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
