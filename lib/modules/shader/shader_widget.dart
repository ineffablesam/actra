import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'shader_controller.dart';

class ShaderWidget extends StatelessWidget {
  const ShaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ShaderController>(
      builder: (controller) {
        final shader = controller.shader;

        // Transparent until shader is ready — no flash, no spinner
        if (shader == null) return const SizedBox.expand();

        return RepaintBoundary(
          child: SizedBox.expand(
            child: ValueListenableBuilder<double>(
              valueListenable: controller.time,
              builder: (context, time, _) {
                return CustomPaint(
                  painter: ShaderPainter(shader: shader, time: time),
                  isComplex: true,
                  willChange: true,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;

  ShaderPainter({required this.shader, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant ShaderPainter oldDelegate) {
    return oldDelegate.time != time;
  }
}
