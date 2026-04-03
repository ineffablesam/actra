import 'dart:async';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class ShaderController extends GetxController
    with GetSingleTickerProviderStateMixin {
  static ShaderController get to => Get.find();

  ui.FragmentShader? shader;
  final time = ValueNotifier<double>(0.0);
  final amplitude = ValueNotifier<double>(0.0);

  Ticker? _ticker;
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSub;

  // Audio player for feedback sounds
  final _audioPlayer = AudioPlayer();

  double _targetAmplitude = 0.0;
  double _smoothedAmplitude = 0.0;

  // ──────────────────────────────────────────────────────────────────────
  // 🎛️ CONFIG
  // ──────────────────────────────────────────────────────────────────────

  final double minDbThreshold = -35.0;
  final double maxDbThreshold = -12.0;
  final double noiseFloor = 0.10;
  final double amplitudeCurve = 2.2;
  final double attackSpeed = 0.35;
  final double releaseSpeed = 0.12;

  final double baseRadius = 2.0;
  final double radiusGrowth = 0.08;
  final double fractalIntensity = 0.10;
  final double colorBoost = 0.35;
  final double glowStrength = 0.65;
  final double zoomAmount = 0.04;
  final double timeScale = 1.0;

  @override
  void onInit() {
    super.onInit();
    _loadShader();
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    // Set audio player mode for quick playback
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.setVolume(1.0);
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/fractal.frag');
    shader = program.fragmentShader();
    _ticker = createTicker(_onTick)..start();
    update();
  }

  void _onTick(Duration elapsed) {
    time.value = elapsed.inMilliseconds / 1000.0 * timeScale;

    final diff = _targetAmplitude - _smoothedAmplitude;
    final speed = diff > 0 ? attackSpeed : releaseSpeed;

    _smoothedAmplitude += diff * speed;
    amplitude.value = _smoothedAmplitude.clamp(0.0, 1.0);
  }

  double _processAmplitude(double rawDb) {
    final db = rawDb.clamp(minDbThreshold, maxDbThreshold);
    final range = maxDbThreshold - minDbThreshold;
    double normalized = (db - minDbThreshold) / range;

    if (normalized < noiseFloor) {
      return 0.0;
    }

    normalized = (normalized - noiseFloor) / (1.0 - noiseFloor);
    normalized = normalized.clamp(0.0, 1.0);

    if (amplitudeCurve > 1.0) {
      normalized = (normalized * normalized * amplitudeCurve).clamp(0.0, 1.0);
    }

    return normalized;
  }

  /// Play activation sound
  Future<void> _playActivateSound() async {
    try {
      await _audioPlayer.stop(); // Stop any current playback
      await _audioPlayer.play(AssetSource('audio/actra_activate.mp3'));
      print('🔊 Playing activation sound');
    } catch (e) {
      print('❌ Error playing activate sound: $e');
    }
  }

  /// Play stop sound
  Future<void> _playStopSound() async {
    try {
      await _audioPlayer.stop(); // Stop any current playback
      await _audioPlayer.play(AssetSource('audio/actra_stop.mp3'));
      print('🔊 Playing stop sound');
    } catch (e) {
      print('❌ Error playing stop sound: $e');
    }
  }

  Future<bool> startListening() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    try {
      // 🔊 Play activation sound FIRST
      unawaited(_playActivateSound());

      final tempDir = await getTemporaryDirectory();
      final audioPath =
          '${tempDir.path}/temp_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: audioPath,
      );

      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 40))
          .listen((amp) {
            _targetAmplitude = _processAmplitude(amp.current);
          });

      return true;
    } catch (e) {
      print('❌ Recording error: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    unawaited(_playStopSound());

    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _recorder.stop();
    _targetAmplitude = 0.0;
  }

  @override
  void onClose() {
    _ticker?.dispose();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    time.dispose();
    amplitude.dispose();
    super.onClose();
  }
}
