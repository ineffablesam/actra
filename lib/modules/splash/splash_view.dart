import 'dart:ui' as ui;

import 'package:actra/utils/custom_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:text_gradiate/text_gradiate.dart';

import '../../utils/colors.dart';
import 'splash_controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(SplashController());

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/images/bg.png")),
        ),
        child: Stack(
          fit: StackFit.expand,
          alignment: .bottomCenter,
          children: [
            Positioned(
              top: -80,
              left: -100,
              child: Image.asset(
                "assets/images/blob.png",
                // fit: BoxFit.cover,
                width: 490.w,
                height: 590.w,
              ),
            ),

            Positioned(
              top: -140,
              left: -270,
              child: SizedBox(
                width: 0.7.sh,
                height: 0.7.sh,
                child: ShaderWidget(),
              ),
            ),
            Positioned(
              top: 0,
              right: 10,
              child: SafeArea(
                top: true,
                child: SvgPicture.asset(
                  "assets/images/autho0.svg",
                  // fit: BoxFit.cover,
                  width: 90.w,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextGradiate(
                  text: Text(
                    'Speak. It acts.',
                    style: GoogleFonts.instrumentSans(
                      fontSize: 26.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  colors: [Colors.black, Color(0xFF8E6BAC)],
                  gradientType: GradientType.linear,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  tileMode: TileMode.clamp,
                ),
                SizedBox(
                  width: 0.8.sw,
                  child: Text(
                    'Actra listens, understands, and executes tasks across your apps — securely and instantly.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.instrumentSans(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.black.withOpacity(0.57),
                    ),
                  ),
                ),
                20.verticalSpace,
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30.w),
                  child: MagicButton(
                    text: "Get Started",
                    onPressed: () {
                      print('Magic button pressed!');
                    },
                  ),
                ),
                0.05.sh.verticalSpace,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MagicButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;

  const MagicButton({Key? key, this.onPressed, this.text = 'Create Magic'})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomTap(
      onTap: onPressed,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(60),
          // Outer border (darker purple)
          // boxShadow: [
          //   BoxShadow(
          //     color: Color(0xFF2D1B4E),
          //     spreadRadius: 10,
          //     blurRadius: 0,
          //     offset: Offset(0, 0),
          //   ),
          // ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(60),
            // Inner border (lighter purple/lavender)
            border: Border.all(color: Color(0xFF632EE4), width: 3),
            // Base purple gradient background
            image: DecorationImage(
              image: AssetImage("assets/images/button_bg.png"),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              // Content
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      text,
                      style: GoogleFonts.instrumentSans(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShaderWidget extends StatefulWidget {
  const ShaderWidget({super.key});

  @override
  State<ShaderWidget> createState() => _ShaderWidgetState();
}

class _ShaderWidgetState extends State<ShaderWidget>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  Ticker? _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/fractal.frag');
    _shader = program.fragmentShader();

    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMilliseconds / 1000.0;
    })..start();

    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RepaintBoundary(
      child: SizedBox.expand(
        child: ValueListenableBuilder<double>(
          valueListenable: _time,
          builder: (context, time, _) {
            return CustomPaint(
              painter: ShaderPainter(shader: _shader!, time: time),
              isComplex: true,
              willChange: true,
            );
          },
        ),
      ),
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
