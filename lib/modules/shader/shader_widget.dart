import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ShaderWidget extends StatelessWidget {
  const ShaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // return GetBuilder<ShaderController>(
    //   builder: (controller) {
    //     if (controller.shader == null) return const SizedBox.expand();
    //
    //     return RepaintBoundary(
    //       child: SizedBox.expand(
    //         child: ListenableBuilder(
    //           listenable: Listenable.merge([
    //             controller.time,
    //             controller.amplitude,
    //           ]),
    //           builder: (_, __) => CustomPaint(
    //             painter: ShaderPainter(
    //               shader: controller.shader!,
    //               time: controller.time.value,
    //               amplitude: controller.amplitude.value,
    //               config: ShaderConfig(
    //                 baseRadius: controller.baseRadius,
    //                 radiusGrowth: controller.radiusGrowth,
    //                 fractalIntensity: controller.fractalIntensity,
    //                 colorBoost: controller.colorBoost,
    //                 glowStrength: controller.glowStrength,
    //                 zoomAmount: controller.zoomAmount,
    //               ),
    //             ),
    //             isComplex: true,
    //             willChange: true,
    //           ),
    //         ),
    //       ),
    //     );
    //   },
    // );
    return SizedBox();
  }
}

class ShaderConfig {
  final double baseRadius;
  final double radiusGrowth;
  final double fractalIntensity;
  final double colorBoost;
  final double glowStrength;
  final double zoomAmount;

  const ShaderConfig({
    required this.baseRadius,
    required this.radiusGrowth,
    required this.fractalIntensity,
    required this.colorBoost,
    required this.glowStrength,
    required this.zoomAmount,
  });
}

class ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final double amplitude;
  final ShaderConfig config;

  const ShaderPainter({
    required this.shader,
    required this.time,
    required this.amplitude,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    shader.setFloat(3, amplitude);

    // Pass configuration to shader
    shader.setFloat(4, config.baseRadius);
    shader.setFloat(5, config.radiusGrowth);
    shader.setFloat(6, config.fractalIntensity);
    shader.setFloat(7, config.colorBoost);
    shader.setFloat(8, config.glowStrength);
    shader.setFloat(9, config.zoomAmount);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant ShaderPainter old) =>
      old.time != time || old.amplitude != amplitude;
}
