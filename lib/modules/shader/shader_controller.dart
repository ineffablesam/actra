import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

class ShaderController extends GetxController
    with GetSingleTickerProviderStateMixin {
  static ShaderController get to => Get.find();

  ui.FragmentShader? shader;
  final time = ValueNotifier<double>(0.0);
  Ticker? _ticker;

  @override
  void onInit() {
    super.onInit();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/fractal.frag');
    shader = program.fragmentShader();
    _ticker = createTicker((elapsed) {
      time.value = elapsed.inMilliseconds / 1000.0;
    })..start();
    update();
  }

  @override
  void onClose() {
    _ticker?.dispose();
    time.dispose();
    super.onClose();
  }
}
