import 'dart:async';
import 'dart:convert';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:get/get.dart';

/// Live TTS playback: streams Cartesia PCM **f32le** chunks via [SoLoud] buffer streams.
///
/// See [flutter_soloud streaming docs](https://docs.page/alnitak/flutter_soloud_docs/advanced/streaming).
class AudioService extends GetxService {
  final isPlaying = false.obs;

  Future<void>? _soloudInit;
  AudioSource? _ttsStream;
  bool _playStarted = false;

  Future<void> _ensureSoloud() async {
    if (SoLoud.instance.isInitialized) return;
    _soloudInit ??= SoLoud.instance.init(sampleRate: 44100);
    await _soloudInit;
  }

  Future<void> _disposeStream(AudioSource? s) async {
    if (s == null) return;
    try {
      await SoLoud.instance.disposeSource(s);
    } catch (_) {}
  }

  /// Feeds base64-encoded PCM chunks; starts playback on first data; ends on [done].
  Future<void> onTtsChunk({
    required String audioBase64,
    required bool done,
    required int sampleRate,
  }) async {
    await _ensureSoloud();

    if (audioBase64.isNotEmpty) {
      final bytes = base64Decode(audioBase64);
      if (bytes.isEmpty) {
        if (done) await _onStreamComplete();
        return;
      }

      if (_ttsStream == null) {
        _ttsStream = SoLoud.instance.setBufferStream(
          maxBufferSizeBytes: 1024 * 1024 * 32,
          bufferingType: BufferingType.released,
          bufferingTimeNeeds: 0.12,
          sampleRate: sampleRate,
          channels: Channels.mono,
          format: BufferType.f32le,
        );
        _playStarted = false;
      }

      SoLoud.instance.addAudioDataStream(_ttsStream!, bytes);

      if (!_playStarted) {
        await SoLoud.instance.play(_ttsStream!);
        _playStarted = true;
        isPlaying.value = true;
      }
    }

    if (done) {
      await _onStreamComplete();
    }
  }

  Future<void> _onStreamComplete() async {
    final s = _ttsStream;
    if (s == null) {
      isPlaying.value = false;
      return;
    }

    try {
      SoLoud.instance.setDataIsEnded(s);
    } catch (_) {}

    _ttsStream = null;
    _playStarted = false;
    isPlaying.value = false;

    unawaited(_disposeStreamAfterPlayback(s));
  }

  Future<void> _disposeStreamAfterPlayback(AudioSource s) async {
    try {
      await s.allInstancesFinished.first
          .timeout(const Duration(minutes: 2));
    } catch (_) {}
    await _disposeStream(s);
  }

  void resetBuffer() {
    final s = _ttsStream;
    _ttsStream = null;
    _playStarted = false;
    isPlaying.value = false;
    unawaited(_disposeStream(s));
  }

  @override
  void onClose() {
    resetBuffer();
    if (SoLoud.instance.isInitialized) {
      SoLoud.instance.deinit();
    }
    super.onClose();
  }
}
