import 'package:flutter_whisper_kit/flutter_whisper_kit.dart';
import 'package:get/get.dart';

/// Single [FlutterWhisperKit] instance for the whole app.
///
/// Creating multiple [FlutterWhisperKit] instances (e.g. splash + audio) can
/// crash the iOS embedder with: `Callback invoked after it has been deleted`.
const String kWhisperModelVariant = 'base';

class WhisperKitService extends GetxService {
  final FlutterWhisperKit plugin = FlutterWhisperKit();
}
