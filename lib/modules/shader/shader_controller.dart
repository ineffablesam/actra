import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

class ShaderController extends GetxController
    with GetSingleTickerProviderStateMixin {
  static ShaderController get to => Get.find();

  ui.FragmentShader? shader;
  final time = ValueNotifier<double>(0.0);
  final amplitude = ValueNotifier<double>(0.0);

  Ticker? _ticker;

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

  /// Called by AudioController with the dB level computed from PCM samples.
  /// This drives the blob animation without needing a separate recorder.
  void updateAmplitudeFromDb(double db) {
    _targetAmplitude = _processAmplitude(db);
  }

  Future<bool> startListening() async {
    return true;
  }

  Future<void> stopListening() async {
    _targetAmplitude = 0.0;
  }

  @override
  void onClose() {
    _ticker?.dispose();
    time.dispose();
    amplitude.dispose();
    super.onClose();
  }
}
