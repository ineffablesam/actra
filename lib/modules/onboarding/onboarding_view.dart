// ── Paste your real paths if they differ ──────────────────────────────────────
import 'package:actra/modules/onboarding/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../shader/shader_widget.dart';

class OnboardingView extends GetView<OnboardingController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(image: AssetImage("assets/images/bg.png")),
          ),
          child: Stack(
            fit: StackFit.expand,
            alignment: .bottomCenter,
            children: [
              Positioned(
                top: -200, // your desired top offset
                left: 0,
                right: 0, // stretch horizontally
                child: Hero(
                  tag: "shader-blob",
                  child: Image.asset(
                    "assets/images/blob.png",
                    // fit: BoxFit.cover,
                    width: 490.w,
                    height: 590.w,
                  ),
                ),
              ),

              Positioned(
                top: -310, // your desired top offset
                left: 0,
                right: 0, // stretch horizontally
                child: SizedBox(
                  width: 0.7.sh,
                  height: 0.7.sh,
                  child: Hero(tag: "shader", child: ShaderWidget()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
