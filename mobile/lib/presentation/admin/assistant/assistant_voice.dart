// =========================================================================
// المساعد الذكي — تسجيل السؤال بالصوت (مكتبة record). WAV أحادي 16kHz: واضح للنسخ وصغير (دقيقة ≈ 2MB).
// الملف مؤقت وينمسح مباشرة بعد ما ينقرأ؛ التسجيل ما ينحفظ بأي مكان.
// =========================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// أقصى طول للتسجيل (نفس حد السيرفر).
const kAssistantMaxRecording = Duration(seconds: 60);

/// واجهة المسجّل (حتى الاختبارات تستعمل مسجّل وهمي).
abstract class AssistantRecorder {
  /// يطلب صلاحية المايك أول مرة؛ false = مرفوضة.
  Future<bool> requestPermission();
  Future<void> start();

  /// يوقف ويرجع التسجيل (null لو ما اكو شي).
  Future<Uint8List?> stop();
  Future<void> cancel();
  void dispose();
}

class RecordAssistantRecorder implements AssistantRecorder {
  final _recorder = AudioRecorder();
  String? _path;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/assistant_question_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: _path!,
    );
  }

  @override
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop() ?? _path;
    _path = null;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    return bytes;
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    _path = null;
  }

  @override
  void dispose() => _recorder.dispose();
}
