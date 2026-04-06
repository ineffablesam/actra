// lib/modules/splash/splash_view.dart

import 'package:actra/modules/shader/shader_widget.dart';
import 'package:actra/modules/splash/splash_controller.dart';
import 'package:actra/utils/colors.dart';
import 'package:actra/utils/custom_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';
import 'package:text_gradiate/text_gradiate.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/chat_mesh_bg_2.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Blob — UNTOUCHED ─────────────────────────────────────────
            Positioned(
              top: -80,
              left: -100,
              child: Hero(
                tag: 'shader-blob',
                child: Image.asset(
                  'assets/images/blob.png',
                  width: 490.w,
                  height: 590.w,
                ),
              ),
            ),

            // ── Shader — UNTOUCHED ───────────────────────────────────────
            Positioned(
              top: -140,
              left: -270,
              child: SizedBox(
                width: 0.7.sh,
                height: 0.7.sh,
                child: Hero(tag: 'shader', child: const ShaderWidget()),
              ),
            ),

            // ── Logo mark — UNTOUCHED ────────────────────────────────────
            Positioned(
              top: 0,
              right: 10,
              child: SafeArea(
                top: true,
                child: SvgPicture.asset(
                  'assets/images/auth0.svg',
                  width: 90.w,
                  color: Colors.white,
                ),
              ),
            ),

            // ── Bottom: swaps between prepare ↔ ready ────────────────────
            Obx(() {
              if (controller.isPreparing.value) {
                return const _BottomPrepare();
              }
              if (controller.isReady.value) {
                return const _BottomReady();
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOTTOM — READY  (original texts + button, slides up on appear)
// ─────────────────────────────────────────────────────────────────────────────

class _BottomReady extends StatefulWidget {
  const _BottomReady();

  @override
  State<_BottomReady> createState() => _BottomReadyState();
}

class _BottomReadyState extends State<_BottomReady>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient headline — exactly as original
              TextGradiate(
                text: Text(
                  'Speak. It acts.',
                  style: GoogleFonts.instrumentSans(
                    fontSize: 26.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                colors: const [Color(0xFFEBD2FF), Color(0xFF8E6BAC)],
                gradientType: GradientType.linear,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                tileMode: TileMode.clamp,
              ),

              SizedBox(height: 4.h),

              // Sub-text — exactly as original
              SizedBox(
                width: 0.8.sw,
                child: Text(
                  'Actra listens, understands, and executes tasks across your apps — securely and instantly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.instrumentSans(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w400,
                    color: Color(0x6BFFFFFF),
                  ),
                ),
              ),

              20.verticalSpace,

              // Button — exactly as original
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 30.w),
                child: MagicButton(
                  text: 'Get Started',
                  onPressed: () async {
                    await Get.find<SplashController>().onGetStarted();
                  },
                ),
              ),

              0.05.sh.verticalSpace,
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOTTOM — PREPARING  (facts + bar + % — replaces the texts+button area only)
// ─────────────────────────────────────────────────────────────────────────────

class _BottomPrepare extends GetView<SplashController> {
  const _BottomPrepare();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(30.w, 0, 30.w, 0.06.sh),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Rotating fact ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: Obx(
                () => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeIn,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Row(
                    key: ValueKey(controller.factIndex.value),
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            'DID YOU KNOW?',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9.sp,
                              color: Colors.white.withOpacity(0.8),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                          SizedBox(height: 5.h),
                          Text(
                            controller.facts[controller.factIndex.value],
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10.sp,
                              color: Colors.white.withOpacity(0.6),
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 22.h),

            // ── Status + file counter row ──────────────────────────────
            Obx(
              () => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      controller.statusText.value,
                      style: GoogleFonts.instrumentSans(
                        fontSize: 11.sp,
                        color: Color(0xFFEBD2FF),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (controller.hasError.value)
                    GestureDetector(
                      onTap: controller.retry,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 3.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.22),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 11.sp,
                              color: Colors.red.shade400,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              'Retry',
                              style: GoogleFonts.instrumentSans(
                                fontSize: 10.sp,
                                color: Colors.red.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      '${controller.currentFile.value} / ${controller.totalFiles.value}',
                      style: GoogleFonts.instrumentSans(
                        fontSize: 11.sp,
                        color: Color(0xFFEBD2FF),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: 8.h),

            // ── Progress track ─────────────────────────────────────────
            Stack(
              children: [
                // Background
                Container(
                  height: 5.h,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 0.8,
                    ),
                  ),
                ),

                // Animated gradient fill
                Obx(() {
                  final trackW = MediaQuery.of(context).size.width - 60.w;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    height: 5.h,
                    width: trackW * controller.progress.value.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF9B72CF),
                          Color(0xFF8E6BAC),
                          Color(0xFF632EE4),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  );
                }),
              ],
            ),

            SizedBox(height: 6.h),

            // ── Percentage label ───────────────────────────────────────
            Obx(() {
              final pct = (controller.progress.value * 100)
                  .clamp(0, 100)
                  .toStringAsFixed(0);
              return Align(
                alignment: Alignment.centerRight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    '$pct%',
                    key: ValueKey(pct),
                    style: GoogleFonts.instrumentSans(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: Color(0x73EBD2FF),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAGIC BUTTON — pixel-perfect copy of your original
// ─────────────────────────────────────────────────────────────────────────────

class MagicButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;

  const MagicButton({super.key, this.onPressed, this.text = 'Create Magic'});

  @override
  Widget build(BuildContext context) {
    return CustomTap(
      onTap: onPressed,
      child: Container(
        height: 60,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(0)),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r),
            border: const GradientBoxBorder(
              gradient: LinearGradient(
                begin: AlignmentGeometry.topLeft,
                end: AlignmentGeometry.bottomRight,
                transform: GradientRotation(1),
                colors: [Color(0xFFFFFFFF), Colors.white10, Color(0xFFFFFFFF)],
              ),
              width: 0.7,
            ),
          ),
          child: Center(
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
                10.horizontalSpace,
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 12.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
