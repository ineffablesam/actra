import 'dart:async';

import 'package:actra/core/auth0_service.dart';
import 'package:actra/core/auth_session_service.dart';
import 'package:actra/routes/app_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_whisper_kit/flutter_whisper_kit.dart';
import 'package:get/get.dart' hide Progress;

/// WhisperKit Core ML variant downloaded on first launch ([WhisperKit docs](https://pub.dev/packages/flutter_whisper_kit)).
const String kWhisperModelVariant = 'base';

class SplashController extends GetxController {
  // ── Observables consumed by SplashView ──────────────────────────────────
  final isPreparing = false.obs;
  final isReady = false.obs;
  final progress = 0.0.obs;
  final statusText = ''.obs;
  final currentFile = 0.obs;
  final totalFiles = 1.obs;
  final hasError = false.obs;
  final factIndex = 0.obs;

  final List<String> facts = const [
    'Actra runs entirely on-device.\nYour voice never leaves your phone.',
    'On-device AI means zero latency —\nno round-trips to the cloud.',
    'WhisperKit uses Apple Neural Engine\nfor ultra-low energy transcription.',
    'Actra understands natural speech,\nnot just rigid commands.',
    'Privacy by design: Actra works\ncompletely offline after setup.',
  ];

  final _whisperKit = FlutterWhisperKit();

  @override
  void onInit() {
    super.onInit();
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(seconds: 2));
    isPreparing.value = true;
    hasError.value = false;
    progress.value = 0.0;
    currentFile.value = 0;
    totalFiles.value = 1;
    statusText.value = 'Preparing AI model…';
    _rotateFacts();
    await _loadModel();
  }

  Future<void> _loadModel() async {
    final loadResult = await _whisperKit.loadModelWithResult(
      kWhisperModelVariant,
      modelRepo: 'argmaxinc/whisperkit-coreml',
      onProgress: (p) {
        progress.value = p.fractionCompleted.clamp(0.0, 1.0);
        if (p.fractionCompleted < 0.99) {
          statusText.value =
              'Downloading AI model… ${(p.fractionCompleted * 100).toStringAsFixed(0)}%';
          currentFile.value = 0;
        } else {
          statusText.value = 'Loading model into memory…';
          currentFile.value = 1;
        }
      },
    );

    loadResult.when(
      success: (modelPath) {
        debugPrint('WhisperKit model ready: $modelPath');
        progress.value = 1.0;
        currentFile.value = 1;
        statusText.value = 'Ready';
        _finishPrepareSuccess();
      },
      failure: (WhisperKitError error) {
        debugPrint(
          'WhisperKit model load failed: ${error.message} (code ${error.code})',
        );
        hasError.value = true;
        statusText.value = 'Failed to load AI model';
      },
    );
  }

  Future<void> _finishPrepareSuccess() async {
    await Future.delayed(const Duration(milliseconds: 600));
    isPreparing.value = false;
    final hasSession = await Get.find<AuthSessionService>().hasCompleteSession();
    if (hasSession) {
      Get.offNamed(Routes.ONBOARDING);
      return;
    }
    isReady.value = true;
  }

  Future<void> onGetStarted() async {
    final ok = await Get.find<Auth0Service>().signIn();
    if (ok) {
      Get.toNamed(Routes.ONBOARDING);
    }
  }

  Future<void> retry() async {
    hasError.value = false;
    progress.value = 0.0;
    statusText.value = 'Retrying…';
    await _loadModel();
  }

  void _rotateFacts() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 4));
      if (!isPreparing.value) return false;
      factIndex.value = (factIndex.value + 1) % facts.length;
      return true;
    });
  }
}
