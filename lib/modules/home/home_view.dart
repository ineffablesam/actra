// lib/modules/home/home_view.dart

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/widgets/chat_message_list.dart';
import 'package:actra/core/auth0_service.dart';
import 'package:actra/core/connectable_providers.dart';
import 'package:actra/modules/audio/audio_controller.dart';
import 'package:actra/modules/connected_accounts/connected_accounts_view.dart';
import 'package:actra/modules/home/home_controller.dart';
import 'package:actra/modules/shader/shader_controller.dart';
import 'package:actra/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
// import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' hide LiquidRoundedSuperellipse, LiquidGlassSettings, LiquidGlassLayer;
import 'package:permission_handler/permission_handler.dart';
import 'package:text_gradiate/text_gradiate.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../utils/custom_tap.dart';
import '../../widgets/realtime_typewriter_transcript.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/chat_mesh_bg_2.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ConnectionSheetHost(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          _HomeSliverAppBar(
                            onLogoutTap: () {
                              final busy =
                                  Get.find<Auth0Service>().isBusy.value;
                              if (busy) return;
                              showLogoutConfirmSheet(context);
                            },
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
                            sliver: const ChatMessagesSliver(),
                          ),
                        ],
                      ),
                      Obx(() {
                        final audioCtrl = AudioController.to;
                        if (!audioCtrl.isListening.value) {
                          return const SizedBox.shrink();
                        }
                        final top =
                            MediaQuery.paddingOf(context).top +
                            _HomeSliverAppBar.toolbarHeight +
                            8.h;
                        return Positioned(
                          top: top,
                          left: 16.w,
                          right: 16.w,
                          child: _TranscriptionDisplay(
                            text: audioCtrl.displayText,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              _BottomControlsBar(
                onAccountsTap: () {
                  showConnectedAccountsSheet(
                    context,
                    providers: kDefaultConnectableProviderIds,
                    reason: 'Connect an account to use Actra with your tools.',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned frosted [SliverAppBar] over the mesh background.
class _HomeSliverAppBar extends StatelessWidget {
  const _HomeSliverAppBar({required this.onLogoutTap});

  static double get toolbarHeight => 52.h;

  final VoidCallback onLogoutTap;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      toolbarHeight: toolbarHeight,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  image: const DecorationImage(
                    image: AssetImage('assets/images/chat_bubble_bg.png'),
                    fit: BoxFit.cover,
                    opacity: 0.9,
                    repeat: ImageRepeat.repeat,
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Image.asset("assets/images/app_icon.png", width: 30.w),
              ),
              5.horizontalSpace,
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello',
                    style: GoogleFonts.instrumentSans(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white60,
                    ),
                  ),
                  TextGradiate(
                    text: Text(
                      'Samuel',
                      style: GoogleFonts.instrumentSans(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    colors: const [Color(0xFFEBD2FF), Color(0xFFFFFFFF)],
                    gradientType: GradientType.linear,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    tileMode: TileMode.clamp,
                  ),
                ],
              ),
            ],
          ),
          Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              image: const DecorationImage(
                image: AssetImage('assets/images/chat_bubble_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.9,
                repeat: ImageRepeat.repeat,
              ),
              borderRadius: BorderRadius.circular(50.r),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Supercharged by',
                    style: GoogleFonts.instrumentSans(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  VerticalDivider(indent: 3, endIndent: 2, color: Colors.white),
                  Padding(
                    padding: EdgeInsets.only(top: 1.h),
                    child: SvgPicture.asset(
                      'assets/images/auth0.svg',
                      width: 65,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Lottie.asset(
          //   'assets/lottie/ai-audio.json',
          //   width: 28.w,
          //   height: 28.h,
          //   fit: BoxFit.cover,
          // ),
        ],
      ),
      centerTitle: true,
      // title: Text(
      //   'Actra',
      //   style: GoogleFonts.instrumentSans(
      //     fontSize: 16.sp,
      //     fontWeight: FontWeight.w700,
      //     // letterSpacing: -0.5,
      //     color: const Color(0xFF1C1C1E),
      //   ),
      // ),
      // actions: [
      //   Obx(() {
      //     final busy = Get.find<Auth0Service>().isBusy.value;
      //     return TextButton(
      //       onPressed: busy ? null : onLogoutTap,
      //       style: TextButton.styleFrom(
      //         foregroundColor: const Color(0xFF007AFF),
      //         padding: EdgeInsets.symmetric(horizontal: 10.w),
      //         minimumSize: Size.zero,
      //         tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      //       ),
      //       child: Row(
      //         mainAxisSize: MainAxisSize.min,
      //         children: [
      //           Icon(Iconsax.logout_1_bold, size: 16.sp),
      //           SizedBox(width: 6.w),
      //           Text(
      //             'Sign out',
      //             style: GoogleFonts.instrumentSans(
      //               fontSize: 15.sp,
      //               fontWeight: FontWeight.w600,
      //             ),
      //           ),
      //         ],
      //       ),
      //     );
      //   }),
      //   SizedBox(width: 4.w),
      //   Obx(() {
      //     final st = Get.find<WebSocketService>().status.value;
      //     final (Color bg, String a11y) = switch (st) {
      //       WsConnectionStatus.connected => (
      //         const Color(0xFF34C759),
      //         'Connected',
      //       ),
      //       WsConnectionStatus.reconnecting => (
      //         const Color(0xFFFF9500),
      //         'Reconnecting',
      //       ),
      //       WsConnectionStatus.disconnected => (
      //         const Color(0xFFFF3B30),
      //         'Disconnected',
      //       ),
      //     };
      //     return Padding(
      //       padding: EdgeInsets.only(right: 12.w),
      //       child: Tooltip(
      //         message: a11y,
      //         child: Container(
      //           width: 9,
      //           height: 9,
      //           decoration: BoxDecoration(
      //             color: bg,
      //             shape: BoxShape.circle,
      //             border: Border.all(
      //               color: Colors.white.withValues(alpha: 0.85),
      //               width: 1.5,
      //             ),
      //           ),
      //         ),
      //       ),
      //     );
      //   }),
      // ],
    );
  }
}

/// Soft fade behind the glass controls (similar to grouped-sheet footers).
class _BottomControlsBar extends StatelessWidget {
  const _BottomControlsBar({required this.onAccountsTap});

  final VoidCallback onAccountsTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Positioned(
        //   left: 0,
        //   right: 0,
        //   bottom: 0,
        //   height: 0.24.sh,
        //   child: IgnorePointer(
        //     child: DecoratedBox(
        //       decoration: BoxDecoration(
        //         gradient: LinearGradient(
        //           begin: Alignment.topCenter,
        //           end: Alignment.bottomCenter,
        //           colors: [
        //             const Color(0x00F2F2F7),
        //             const Color(0xB8F2F2F7),
        //             const Color(0xE8F2F2F7),
        //           ],
        //           stops: const [0.0, 0.45, 1.0],
        //         ),
        //       ),
        //     ),
        //   ),
        // ),
        Padding(
          padding: EdgeInsets.only(bottom: 0.05.sh),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              CustomTap(
                onTap: onAccountsTap,
                child: Center(
                  child: LiquidGlassLayer(
                    settings: const LiquidGlassSettings(
                      thickness: 20,
                      blur: 10,
                      glassColor: Color(0x30121B49),
                    ),
                    child: LiquidStretch(
                      stretch: 0.5,
                      interactionScale: 1.05,
                      child: LiquidGlass(
                        shape: LiquidRoundedSuperellipse(borderRadius: 50),
                        child: SizedBox(
                          height: 60,
                          width: 60,
                          child: Center(
                            child: Icon(
                              EvaIcons.link_2_outline,
                              color: Color(0xFFFFFFFF),
                              size: 24.sp,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // GlassIconButton(
              //   size: 60,
              //   icon: Icon(
              //     Iconsax.shield_security,
              //     color: const Color(0xFF1C1C1E),
              //     size: 24.sp,
              //   ),
              //   onPressed: onAccountsTap,
              // ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 28.w),
                child: const MagicButton(),
              ),
              Center(
                child: LiquidGlassLayer(
                  settings: const LiquidGlassSettings(
                    thickness: 20,
                    blur: 10,
                    glassColor: Color(0x30121B49),
                  ),
                  child: LiquidStretch(
                    stretch: 0.5,
                    interactionScale: 1.05,
                    child: LiquidGlass(
                      shape: LiquidRoundedSuperellipse(borderRadius: 50),
                      child: SizedBox(
                        height: 60,
                        width: 60,
                        child: Center(
                          child: Icon(
                            Iconsax.setting_2_bold,
                            color: Color(0xFFFFFFFF),
                            size: 24.sp,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // GlassIconButton(
              //   size: 60,
              //   icon: Icon(
              //     Iconsax.setting_2,
              //     color: const Color(0xFF1C1C1E),
              //     size: 24.sp,
              //   ),
              //   onPressed: () {},
              // ),
            ],
          ),
        ),
      ],
    );
  }
}

void showLogoutConfirmSheet(BuildContext context) {
  unawaited(
    WoltModalSheet.show<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      modalBarrierColor: Colors.black26,
      enableDrag: true,
      showDragHandle: true,
      modalTypeBuilder: (_) => const WoltBottomSheetType(),
      pageListBuilder: (modalSheetContext) => [
        WoltModalSheetPage(
          backgroundColor: const Color(0xFFF2F2F7),
          surfaceTintColor: Colors.transparent,
          hasTopBarLayer: true,
          isTopBarLayerAlwaysVisible: true,
          topBarTitle: Text(
            'Sign out',
            style: GoogleFonts.instrumentSans(
              fontSize: 17.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.41,
              color: Colors.black,
            ),
          ),
          trailingNavBarWidget: IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 22.sp,
              color: const Color(0xFF007AFF),
            ),
            onPressed: () => Navigator.of(modalSheetContext).pop(),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You will need to sign in again to use Actra.',
                  style: GoogleFonts.instrumentSans(
                    fontSize: 15.sp,
                    color: const Color(0x993C3C43),
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 24.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(modalSheetContext).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          foregroundColor: const Color(0xFF007AFF),
                          side: const BorderSide(color: Color(0x4C3C3C43)),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.instrumentSans(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.of(modalSheetContext).pop();
                          final busy = Get.find<Auth0Service>().isBusy.value;
                          if (busy) return;
                          await Get.find<Auth0Service>().signOut();
                          Get.offAllNamed(Routes.SPLASH);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B30),
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                        ),
                        child: Text(
                          'Sign out',
                          style: GoogleFonts.instrumentSans(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Transcription Display (when listening)
// ─────────────────────────────────────────────────────────────────────────────

class _TranscriptionDisplay extends StatelessWidget {
  final String text;

  const _TranscriptionDisplay({required this.text});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: 0.28.sh, minHeight: 76.h),
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x33000000)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            reverse: true,
            physics: const BouncingScrollPhysics(),
            child: RealtimeTypewriterTranscript(
              text: text.isEmpty ? 'Listening...' : text,
              placeholderStyle: GoogleFonts.instrumentSans(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0x993C3C43),
                height: 1.45,
              ),
              style: GoogleFonts.instrumentSans(
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1C1C1E),
                height: 1.45,
              ),
            ),
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

  // ── Icon cross-fade ──────────────────────────────────────────────────────
  late final AnimationController _iconCtrl;
  late final Animation<double> _micIdleOpacity;
  late final Animation<double> _micOnOpacity;

  // ── Button scale — driven by a SpringSimulation ──────────────────────────
  late final AnimationController _scaleCtrl;
  late final Animation<double> _iconScale;

  // ── Pulse ring ───────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  // ── Amplitude glow ───────────────────────────────────────────────────────
  late final AnimationController _ampCtrl;
  double _targetAmp = 0.0;

  @override
  void initState() {
    super.initState();

    // ── Icon cross-fade controller (simple fade, no scale here) ─────────────
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _micIdleOpacity = CurvedAnimation(
      parent: ReverseAnimation(_iconCtrl),
      curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
    );
    _micOnOpacity = CurvedAnimation(
      parent: _iconCtrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );

    // ── Scale spring controller (unbounded so spring can overshoot) ──────────
    _scaleCtrl = AnimationController(
      vsync: this,
      // upperBound allows overshoot above 1.0
      lowerBound: 0.0,
      upperBound: 2.0,
      value: 1.0,
    );
    _iconScale = _scaleCtrl; // controller IS the value (0-2 range)

    // ── Pulse — use a symmetric curve so repeat() has no hard jump ───────────
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseScale = Tween(
      begin: 1.0,
      end: 1.44,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseOpacity = Tween(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeIn));

    // ── Amplitude — single long-lived controller, smoothed by spring ─────────
    _ampCtrl = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.0,
    );

    ShaderController.to.amplitude.addListener(_onAmplitude);
  }

  // ── Spring helpers ────────────────────────────────────────────────────────

  /// Drives [ctrl] toward [target] using a spring simulation.
  /// stiffness / damping tune the feel:
  ///   - higher stiffness → snappier
  ///   - critical damping ratio = 1.0 → no overshoot; < 1.0 → bouncy
  void _springTo(
    AnimationController ctrl,
    double target, {
    double stiffness = 200,
    double damping = 26,
    double mass = 1.0,
  }) {
    final velocity = ctrl.velocity; // preserve momentum
    final sim = _SpringSimulation(
      stiffness: stiffness,
      damping: damping,
      mass: mass,
      start: ctrl.value,
      end: target,
      velocity: velocity,
    );
    ctrl.animateWith(sim);
  }

  void _onAmplitude() {
    if (!mounted) return;
    _targetAmp = ShaderController.to.amplitude.value;
    // Spring-drive the amp controller — replaces rapid animateTo() calls
    _springTo(_ampCtrl, _targetAmp, stiffness: 180, damping: 22);
  }

  @override
  void dispose() {
    ShaderController.to.amplitude.removeListener(_onAmplitude);
    _iconCtrl.dispose();
    _scaleCtrl.dispose();
    _pulseCtrl.dispose();
    _ampCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isAnimating) return;
    _isAnimating = true;
    HapticFeedback.mediumImpact();

    if (!_isListening) {
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

      setState(() => _isListening = true);
      _iconCtrl.forward();
      _pulseCtrl.repeat();

      // Spring: compress then overshoot to 1.0 — feels like a physical tap
      _scaleCtrl.value = 1.0;
      _springTo(_scaleCtrl, 0.82, stiffness: 600, damping: 28);
      await Future.delayed(const Duration(milliseconds: 80));
      _springTo(_scaleCtrl, 1.0, stiffness: 260, damping: 18); // bouncy release

      final shaderStarted = await ShaderController.to.startListening();
      final audioStarted = await AudioController.to.startListening();

      if (!shaderStarted || !audioStarted) {
        setState(() => _isListening = false);
        _iconCtrl.reverse();
        _pulseCtrl.stop();
        _pulseCtrl.reset();
        _springTo(_scaleCtrl, 1.0, stiffness: 260, damping: 24);
        _isAnimating = false;
        return;
      }
    } else {
      setState(() => _isListening = false);
      _iconCtrl.reverse();
      _pulseCtrl.stop();
      _pulseCtrl.reset();

      // Spring amp back to zero smoothly
      _springTo(_ampCtrl, 0.0, stiffness: 120, damping: 20);

      // Gentle tap-off feel
      _springTo(_scaleCtrl, 0.88, stiffness: 500, damping: 30);
      await Future.delayed(const Duration(milliseconds: 70));
      _springTo(_scaleCtrl, 1.0, stiffness: 200, damping: 22);

      await AudioController.to.stopListening();
      await ShaderController.to.stopListening();

      final spoken = AudioController.to.transcribedText.value.trim();
      if (spoken.isNotEmpty) {
        Get.find<ChatController>().sendUserTranscript(spoken);
      }
    }

    await Future.delayed(const Duration(milliseconds: 380));
    _isAnimating = false;
  }

  @override
  Widget build(BuildContext context) {
    final buttonSize = 80.w;

    return CustomTap(
      onTap: _handleTap,
      child: SizedBox(
        width: 90.w,
        height: 90.w,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Pulse ring ─────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
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

            // ── Outer gradient border ring (2px) ───────────────────────────
            Container(
              width: buttonSize + 90,
              height: buttonSize + 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  transform: GradientRotation(0.8),
                  colors: [
                    Color(0xFF000000), // black
                    Color(0xFFB454FF), // purple
                    Color(0xFFEBD2FF), // lighter purple
                    Color(0xFF000000), // back to black
                  ],
                  stops: [0.0, 0.6, 0.7, 1.0],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0), // this is the border width
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors
                        .black, // mask the inside so only the 2px ring shows
                  ),
                ),
              ),
            ),

            // ── Second outer border ring (thin, semi-transparent) ──────────
            Container(
              width: buttonSize + 28,
              height: buttonSize + 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x33C2A8FF), width: 90),
              ),
            ),

            // ── Button body ────────────────────────────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([_scaleCtrl, _ampCtrl]),
              builder: (context, _) {
                final amp = _ampCtrl.value;
                final glowRadius = _isListening ? 12.0 + amp * 24.0 : 0.0;
                final glowOpacity = _isListening ? 0.30 + amp * 0.50 : 0.0;

                return Transform.scale(
                  scale: _iconScale.value,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // ── Button base with image + glow ─────────────────
                      Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          image: const DecorationImage(
                            image: AssetImage("assets/images/button_bg_2.png"),
                            fit: BoxFit.cover,
                          ),
                          // boxShadow: glowRadius > 0
                          //     ? [
                          //         BoxShadow(
                          //           color: const Color(
                          //             0xFF7C3AED,
                          //           ).withValues(alpha: glowOpacity),
                          //           blurRadius: glowRadius,
                          //           spreadRadius: glowRadius * 0.9,
                          //         ),
                          //       ]
                          //     : null,
                        ),
                      ),

                      // ── Inner shadow overlay (top white highlight + bottom dark) ──
                      Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(
                                alpha: 0.18,
                              ), // subtle white sheen at top
                              Colors.transparent,
                              Colors.black.withValues(
                                alpha: 0.15,
                              ), // dark at bottom
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),

                      // ── Icons ─────────────────────────────────────────
                      FadeTransition(
                        opacity: _micIdleOpacity,
                        child: Icon(
                          Iconsax.microphone_bold,
                          color: Colors.white,
                          size: 26.sp,
                        ),
                      ),
                      FadeTransition(
                        opacity: _micOnOpacity,
                        child: Icon(
                          Iconsax.microphone_slash_1_bold,
                          color: Colors.white,
                          size: 26.sp,
                        ),
                      ),
                    ],
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

class _SpringSimulation extends Simulation {
  _SpringSimulation({
    required double stiffness,
    required double damping,
    required double mass,
    required double start,
    required double end,
    required double velocity,
  }) : _start = start,
       _end = end,
       _sim = SpringSimulation(
         SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
         start,
         end,
         velocity,
       );

  final double _start;
  final double _end;
  final SpringSimulation _sim;

  @override
  double x(double time) => _sim.x(time);

  @override
  double dx(double time) => _sim.dx(time);

  @override
  bool isDone(double time) => _sim.isDone(time);
}
