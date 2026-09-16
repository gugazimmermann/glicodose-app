import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SpeechService {
  SpeechService(this._client);

  final SupabaseClient _client;
  final AudioRecorder _recorder = AudioRecorder();
  final _uuid = const Uuid();

  String? _activePath;
  bool get isRecording => _activePath != null;

  Future<void> ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return;

    status = await Permission.microphone.request();
    if (status.isGranted) return;

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception(
        'Microfone bloqueado. Ative a permissão nas configurações do app e tente de novo.',
      );
    }
    throw Exception('Permissão de microfone necessária para falar.');
  }

  Future<void> startRecording() async {
    await ensureMicPermission();

    if (!await _recorder.hasPermission()) {
      throw Exception('Permissão de microfone necessária para falar.');
    }

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'food_${_uuid.v4()}.m4a');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    _activePath = path;
  }

  /// Stops recording and returns Whisper transcript text.
  Future<String> stopAndTranscribe() async {
    final path = await _recorder.stop();
    final recordedPath = path ?? _activePath;
    _activePath = null;

    if (recordedPath == null || recordedPath.isEmpty) {
      throw Exception('Nenhum áudio gravado.');
    }

    final file = File(recordedPath);
    try {
      if (!await file.exists()) {
        throw Exception('Arquivo de áudio não encontrado.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 64) {
        throw Exception('Áudio muito curto. Fale um pouco mais e tente de novo.');
      }

      final response = await _client.functions.invoke(
        'transcribe-food',
        body: {
          'audio_base64': base64Encode(bytes),
          'mime_type': 'audio/mp4',
          'file_name': p.basename(recordedPath),
        },
      );

      if (response.status != 200) {
        final error = response.data;
        final message = error is Map && error['error'] != null
            ? error['error'].toString()
            : 'Falha ao transcrever (${response.status})';
        throw Exception(message);
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      final text = (data['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        throw Exception('Nenhuma fala reconhecida.');
      }
      return text;
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> cancelRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    final path = _activePath;
    _activePath = null;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await cancelRecording();
    await _recorder.dispose();
  }
}
