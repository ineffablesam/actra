import 'dart:async';

import 'package:actra/chat/services/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_whisper_kit/flutter_whisper_kit.dart';
import 'package:get/get.dart';

/// Real-time STT using the same **Dart API** as the package README:
/// subscribe to [FlutterWhisperKit.transcriptionStream], then
/// [FlutterWhisperKit.startRecording], then [FlutterWhisperKit.stopRecording].
/// The `base` model is loaded on splash.
///
/// **Why you see “Not enough audio data” and ~1s delay (not something we add in Dart):**
/// The iOS implementation in `flutter_whisper_kit_apple` only runs Whisper after the
/// live buffer exceeds **1 second** of audio (`bufferSeconds > 1.0` in
/// `transcribeCurrentBufferInternal`). Whisper needs enough PCM to build mel frames;
/// that guard is fixed in native code — it cannot be removed from Dart without forking the plugin.
///
/// **Why it feels “laggy” or the sentence keeps changing:**
/// The native loop wakes about every **300ms**, runs inference on the **current rolling buffer**,
/// and emits a **full** partial string each time — not word-by-word tokens. So text updates in
/// chunks and earlier phrases can be revised as the buffer grows. That’s WhisperKit’s design here,
/// not GetX or Flutter.
///
/// **`CancellationError` on stop:** The realtime loop is cancelled in native code when recording
/// stops; Swift often logs that. It does not mean your transcript was lost — we keep the last
/// good partial from the stream.
///
/// The README shows `stopRecording` then `finalTranscription?.text`; in v0.3.x `stopRecording`
/// actually returns `String?` (e.g. `"Recording stopped"`), so live text must come from the stream.
///
/// **UI sounds:** MP3 cues use [AudioPlayer] only **before** [FlutterWhisperKit.startRecording]
/// or **after** [FlutterWhisperKit.stopRecording] plus a short delay — never while the mic is
/// capturing, to avoid AVAudioSession / audio focus clashes. TTS is stopped via [_stopTtsIfPlaying]
/// before the pre-roll sound.
class AudioController extends GetxController {
  static AudioController get to => Get.find();

  final isListening = false.obs;
  final transcribedText = ''.obs;
  final partialText = ''.obs;

  final _whisperKit = FlutterWhisperKit();

  final AudioPlayer _sfxPlayer = AudioPlayer();

  StreamSubscription<TranscriptionResult>? _transcriptionSub;

  static const String _activateAsset = 'audio/actra_activate.mp3';
  static const String _stopAsset = 'audio/actra_stop.mp3';

  @override
  void onInit() {
    super.onInit();
    unawaited(_configureSfxPlayer());
  }

  Future<void> _configureSfxPlayer() async {
    await _sfxPlayer.setReleaseMode(ReleaseMode.stop);
    await _sfxPlayer.setPlayerMode(PlayerMode.lowLatency);
  }

  /// Activate chirp runs to completion, then recording starts — never overlaps capture.
  Future<void> _playActivateSfxFull() async {
    await _sfxPlayer.stop();
    await _sfxPlayer.play(AssetSource(_activateAsset));
    try {
      await _sfxPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      await _sfxPlayer.stop();
    }
  }

  /// After the mic is fully released; optional delay is applied by the caller.
  Future<void> _playStopSfx() async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource(_stopAsset));
    } catch (_) {}
  }

  /// Stops TTS ([AudioService] / flutter_soloud) so only one native audio graph is active with the mic.
  void _stopTtsIfPlaying() {
    if (!Get.isRegistered<AudioService>()) return;
    try {
      Get.find<AudioService>().resetBuffer();
    } catch (_) {}
  }

  /// Tuned for **English** realtime accuracy: deterministic decode, VAD chunking,
  /// prefill cache (matches package `RecordingService` defaults), no auto language
  /// detection, no word-level timestamps (cleaner partials; enable if you need timings).
  static const _decodingOptions = DecodingOptions(
    verbose: false,
    task: DecodingTask.transcribe,
    language: 'en',
    temperature: 0.0,
    temperatureIncrementOnFallback: 0.2,
    temperatureFallbackCount: 5,
    sampleLength: 224,
    topK: 5,
    usePrefillPrompt: true,
    usePrefillCache: true,
    detectLanguage: false,
    skipSpecialTokens: true,
    withoutTimestamps: false,
    wordTimestamps: false,
    maxInitialTimestamp: 1.0,
    clipTimestamps: [0.0],
    concurrentWorkerCount: 4,
    chunkingStrategy: ChunkingStrategy.vad,
    noSpeechThreshold: 0.6,
    logProbThreshold: -1.0,
    firstTokenLogProbThreshold: -1.5,
  );

  Future<bool> startListening() async {
    debugPrint(
      '🎤 Start listening (WhisperKit base model should be loaded on splash)…',
    );
    try {
      transcribedText.value = '';
      partialText.value = '';
      isListening.value = true;

      _stopTtsIfPlaying();

      if (!kDebugMode) {
        try {
          await _playActivateSfxFull();
        } catch (e) {
          debugPrint('Activate SFX skipped: $e');
        }
      }

      await _transcriptionSub?.cancel();
      _transcriptionSub = _whisperKit.transcriptionStream.listen(
        (transcription) {
          final text = transcription.text.trim();
          if (text.isNotEmpty) {
            debugPrint('Real-time transcription: $text');
            partialText.value = text;
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('Transcription stream error: $e');
        },
      );

      await _whisperKit.startRecording(options: _decodingOptions, loop: true);

      debugPrint('✅ Recording started — speak for ~1s+ for first text');
      return true;
    } catch (e) {
      debugPrint('❌ Start listening error: $e');
      isListening.value = false;
      await _transcriptionSub?.cancel();
      _transcriptionSub = null;
      return false;
    }
  }

  Future<void> stopListening() async {
    debugPrint('🛑 Stopping recording…');

    // Snapshot + leave listening state immediately so UI matches the mic button.
    if (partialText.value.isNotEmpty) {
      transcribedText.value = partialText.value;
    }
    isListening.value = false;
    partialText.value = '';

    try {
      final finalMessage = await _whisperKit.stopRecording(loop: true);
      debugPrint('Final transcription (status line): $finalMessage');
    } catch (e) {
      debugPrint('❌ Stop error: $e');
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));

    await _transcriptionSub?.cancel();
    _transcriptionSub = null;

    // Mic is off; brief pause so the OS is not still in record mode, then play stop cue.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!kDebugMode) {
      await _playStopSfx();
    }

    debugPrint('✅ Stopped');
  }

  String get displayText {
    if (isListening.value) {
      return partialText.value.isEmpty ? 'Listening...' : partialText.value;
    }
    return transcribedText.value;
  }

  @override
  void onClose() {
    _transcriptionSub?.cancel();
    unawaited(_sfxPlayer.dispose());
    super.onClose();
  }
}
