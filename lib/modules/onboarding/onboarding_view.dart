// lib/modules/onboarding/onboarding_view.dart

import 'package:actra/modules/audio/audio_controller.dart';
import 'package:actra/modules/onboarding/onboarding_controller.dart';
import 'package:actra/modules/shader/shader_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:text_gradiate/text_gradiate.dart';

import '../../utils/custom_tap.dart';
import '../../widgets/realtime_typewriter_transcript.dart';
import '../shader/shader_widget.dart';

class OnboardingView extends GetView<OnboardingController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize AudioController
    Get.put(AudioController());

    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage("assets/images/bg.png")),
          ),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.bottomCenter,
            children: [
              // ── Blob background ──────────────────────────────────────────
              Positioned(
                top: -200,
                left: 0,
                right: 0,
                child: Hero(
                  tag: "shader-blob",
                  child: Image.asset(
                    "assets/images/blob.png",
                    width: 490.w,
                    height: 590.w,
                  ),
                ),
              ),

              // ── Marble shader oval ───────────────────────────────────────
              Positioned(
                top: -310,
                left: 0,
                right: 0,
                child: SizedBox(
                  width: 0.7.sh,
                  height: 0.7.sh,
                  child: const Hero(tag: "shader", child: ShaderWidget()),
                ),
              ),

              // ── Foreground UI ────────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  const Spacer(),

                  // ── Text Area (Welcome OR Transcription) ───────────────
                  Obx(() {
                    final audioCtrl = AudioController.to;
                    final isListening = audioCtrl.isListening.value;
                    final displayText = audioCtrl.displayText;

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      child: isListening
                          ? _TranscriptionDisplay(
                              key: ValueKey('transcription'),
                              text: displayText,
                            )
                          : _WelcomeText(key: ValueKey('welcome')),
                    );
                  }),

                  const Spacer(),

                  // ── Bottom Controls ────────────────────────────────────
                  GlassTheme(
                    data: GlassThemeData(
                      light: GlassThemeVariant(
                        settings: LiquidGlassSettings(thickness: 90, blur: 10),
                        quality: GlassQuality.standard,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        GlassIconButton(
                          size: 60,
                          icon: const Icon(
                            Iconsax.shield_security,
                            color: Colors.black,
                          ),
                          onPressed: () {},
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 30.w),
                          child: const MagicButton(),
                        ),
                        GlassIconButton(
                          size: 60,
                          icon: const Icon(
                            Iconsax.setting_2,
                            color: Colors.black,
                          ),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 0.05.sh),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome Text (when NOT listening)
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeText extends StatelessWidget {
  const _WelcomeText({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      child: TextGradiate(
        text: Text(
          'Hi Samuel! 👋 I\'m Actra, your AI assistant. '
          'Speak naturally and I\'ll make it happen. '
          'Ask me anything.',
          textAlign: TextAlign.center,
          style: GoogleFonts.instrumentSans(
            fontSize: 16.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        colors: const [Colors.black, Color(0xFF8E6BAC)],
        gradientType: GradientType.linear,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        tileMode: TileMode.clamp,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transcription Display (when listening)
// ─────────────────────────────────────────────────────────────────────────────

class _TranscriptionDisplay extends StatelessWidget {
  final String text;

  const _TranscriptionDisplay({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: 0.3.sh, minHeight: 80.h),
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
      child: SingleChildScrollView(
        reverse: true, // Latest text at bottom
        child: RealtimeTypewriterTranscript(
          text: text.isEmpty ? 'Listening...' : text,
          placeholderStyle: GoogleFonts.instrumentSans(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: Colors.black.withOpacity(0.4),
            height: 1.5,
          ),
          style: GoogleFonts.instrumentSans(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.black.withOpacity(0.85),
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Magic Button (updated to control AudioController)
// ─────────────────────────────────────────────────────────────────────────────

class MagicButton extends StatefulWidget {
  const MagicButton({super.key});

  @override
  State<MagicButton> createState() => _MagicButtonState();
}

class _MagicButtonState extends State<MagicButton>
    with TickerProviderStateMixin {
  bool _isListening = false;
  bool _isAnimating = false;

  late final AnimationController _iconCtrl;
  late final Animation<double> _micIdleOpacity;
  late final Animation<double> _micOnOpacity;
  late final Animation<double> _iconScale;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  late final AnimationController _ampCtrl;

  @override
  void initState() {
    super.initState();

    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _micIdleOpacity = CurvedAnimation(
      parent: ReverseAnimation(_iconCtrl),
      curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
    );

    _micOnOpacity = CurvedAnimation(
      parent: _iconCtrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );

    _iconScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.75,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.75,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 55,
      ),
    ]).animate(_iconCtrl);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween(
      begin: 1.0,
      end: 1.42,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween(
      begin: 0.60,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

    _ampCtrl = AnimationController(vsync: this, value: 0.0);
    ShaderController.to.amplitude.addListener(_onAmplitude);
  }

  void _onAmplitude() {
    if (!mounted) return;
    final target = ShaderController.to.amplitude.value;
    _ampCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    ShaderController.to.amplitude.removeListener(_onAmplitude);
    _iconCtrl.dispose();
    _pulseCtrl.dispose();
    _ampCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isAnimating) return;
    _isAnimating = true;
    HapticFeedback.mediumImpact();

    if (!_isListening) {
      // Request permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _isAnimating = false;
        Get.snackbar(
          'Microphone',
          'Please allow microphone access in Settings.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // React immediately — do not wait for SFX or Whisper init.
      setState(() => _isListening = true);
      _iconCtrl.forward();
      _pulseCtrl.repeat();

      final shaderStarted = await ShaderController.to.startListening();
      final audioStarted = await AudioController.to.startListening();

      if (!shaderStarted || !audioStarted) {
        setState(() => _isListening = false);
        _iconCtrl.reverse();
        _pulseCtrl.stop();
        _pulseCtrl.reset();
        _isAnimating = false;
        return;
      }
    } else {
      setState(() => _isListening = false);
      _iconCtrl.reverse();
      _pulseCtrl.stop();
      _pulseCtrl.reset();

      await AudioController.to.stopListening();
      await ShaderController.to.stopListening();
    }

    await Future.delayed(const Duration(milliseconds: 420));
    _isAnimating = false;
  }

  @override
  Widget build(BuildContext context) {
    final buttonSize = 80.w;

    return CustomTap(
      onTap: _handleTap,
      child: SizedBox(
        width: 104.w,
        height: 104.w,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                if (!_isListening && _pulseCtrl.value == 0.0) {
                  return const SizedBox.shrink();
                }
                return Transform.scale(
                  scale: _pulseScale.value,
                  child: Opacity(
                    opacity: _pulseOpacity.value,
                    child: Container(
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF632EE4),
                          width: 2.0,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Button body
            AnimatedBuilder(
              animation: Listenable.merge([_iconCtrl, _ampCtrl]),
              builder: (_, __) {
                final scale = _iconScale.value;
                final glowRadius = _isListening
                    ? 12.0 + _ampCtrl.value * 24.0
                    : 0.0;
                final glowOpacity = _isListening
                    ? 0.30 + _ampCtrl.value * 0.50
                    : 0.0;

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0x6E4A00FD),
                        width: 10.w,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      image: const DecorationImage(
                        image: AssetImage("assets/images/button_bg.png"),
                        fit: BoxFit.cover,
                      ),
                      boxShadow: glowRadius > 0
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF7C3AED,
                                ).withOpacity(glowOpacity),
                                blurRadius: glowRadius,
                                spreadRadius: glowRadius * 0.3,
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        FadeTransition(
                          opacity: _micIdleOpacity,
                          child: Icon(
                            Iconsax.microphone,
                            color: Colors.white,
                            size: 26.sp,
                          ),
                        ),
                        FadeTransition(
                          opacity: _micOnOpacity,
                          child: Icon(
                            Iconsax.microphone_slash,
                            color: Colors.white,
                            size: 26.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
