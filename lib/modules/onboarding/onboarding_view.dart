import 'dart:async';

// ── Paste your real paths if they differ ──────────────────────────────────────
import 'package:actra/modules/onboarding/onboarding_controller.dart';
import 'package:actra/utils/sf_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';
import 'package:sprung/sprung.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NEWS-CARD DATA  (swap asset paths for real ones)
// ─────────────────────────────────────────────────────────────────────────────
const List<String> _cardImages = [
  'assets/images/news_1.png',
  'assets/images/news_2.png',
  'assets/images/news_3.png',
  'assets/images/news_4.png',
  'assets/images/news_5.png',
  'assets/images/news_6.png',
  'assets/images/news_7.png',
  'assets/images/news_8.png',
];

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE CARD  (static — no per-card animation, row handles the reveal)
// ─────────────────────────────────────────────────────────────────────────────
class _NewsCard extends StatelessWidget {
  final String imagePath;
  final double width;
  final double height;

  const _NewsCard({
    required this.imagePath,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade300,
            child: Icon(
              Icons.image_outlined,
              size: 32.sp,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARQUEE ROW  (auto-scrolling with a clean fade-in on first appearance)
// ─────────────────────────────────────────────────────────────────────────────
class _MarqueeRow extends StatefulWidget {
  final List<String> images;
  final double cardW;
  final double cardH;
  final double gap;
  final bool reverse;
  final Duration speed;
  final Duration entryDelay;

  const _MarqueeRow({
    required this.images,
    required this.cardW,
    required this.cardH,
    required this.gap,
    this.reverse = false,
    this.speed = const Duration(seconds: 3),
    this.entryDelay = Duration.zero,
  });

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow>
    with TickerProviderStateMixin {
  late AnimationController _scrollCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;
  late Animation<Offset> _rise;

  @override
  void initState() {
    super.initState();

    // ── Scroll controller ──────────────────────────────────────────────────
    _scrollCtrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: widget.speed.inMilliseconds * widget.images.length,
      ),
    )..repeat();

    // ── Single fade+rise reveal for the whole row ──────────────────────────
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _rise = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Sprung.overDamped));

    Future.delayed(widget.entryDelay, () {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Duplicate list so it feels infinite
    final doubled = [...widget.images, ...widget.images];
    final itemWidth = widget.cardW + widget.gap;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _rise,
        child: SizedBox(
          height: widget.cardH,
          child: AnimatedBuilder(
            animation: _scrollCtrl,
            builder: (_, __) {
              final totalWidth = itemWidth * widget.images.length;
              double offset = _scrollCtrl.value * totalWidth;
              if (widget.reverse) offset = totalWidth - offset;

              return OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(-offset, 0),
                  child: Row(
                    children: doubled.map((img) {
                      return Padding(
                        padding: EdgeInsets.only(right: widget.gap),
                        child: _NewsCard(
                          imagePath: img,
                          width: widget.cardW,
                          height: widget.cardH,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKDROP  (rotated marquee grid + white gradient overlay)
// ─────────────────────────────────────────────────────────────────────────────
class _AnimatedBackdrop extends StatelessWidget {
  const _AnimatedBackdrop();

  @override
  Widget build(BuildContext context) {
    final cardW = 140.w;
    final cardH = 180.h;
    const gap = 12.0;
    const angle = -0.18; // ~-10°

    final screenH = 1.sh;
    final screenW = 1.sw;
    final expandedH = screenH * 1.6;

    return SoftEdgeBlur(
      edges: [
        EdgeBlur(
          type: EdgeType.topEdge,
          size: 100,
          sigma: 50,
          tintColor: Colors.black38,
          controlPoints: [
            ControlPoint(position: 0.5, type: ControlPointType.visible),
            ControlPoint(position: 1, type: ControlPointType.transparent),
          ],
        ),
      ],
      child: SizedBox(
        width: screenW,
        height: screenH,
        child: Stack(
          children: [
            // ── Rotated card grid ──────────────────────────────────────────
            Positioned.fill(
              child: OverflowBox(
                maxHeight: expandedH,
                maxWidth: screenW * 1.4,
                alignment: Alignment.topCenter,
                child: Transform.rotate(
                  angle: angle,
                  child: Column(
                    children: [
                      SizedBox(height: 0.h),
                      _MarqueeRow(
                        images: _cardImages,
                        cardW: cardW,
                        cardH: cardH,
                        gap: gap,
                        reverse: false,
                        speed: const Duration(seconds: 4),
                        entryDelay: const Duration(milliseconds: 0),
                      ),
                      SizedBox(height: gap),
                      _MarqueeRow(
                        images: [..._cardImages.reversed],
                        cardW: cardW,
                        cardH: cardH,
                        gap: gap,
                        reverse: true,
                        speed: const Duration(seconds: 4),
                        entryDelay: const Duration(milliseconds: 100),
                      ),
                      SizedBox(height: gap),
                      _MarqueeRow(
                        images: _cardImages,
                        cardW: cardW,
                        cardH: cardH,
                        gap: gap,
                        reverse: false,
                        speed: const Duration(seconds: 5),
                        entryDelay: const Duration(milliseconds: 200),
                      ),
                      SizedBox(height: gap),
                      _MarqueeRow(
                        images: [..._cardImages.reversed],
                        cardW: cardW,
                        cardH: cardH,
                        gap: gap,
                        reverse: true,
                        speed: const Duration(seconds: 4),
                        entryDelay: const Duration(milliseconds: 300),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── White gradient fade from bottom ───────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.35, 0.6, 1.0],
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.82),
                      Colors.white,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.35, 0.6, 1.0],
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.82),
                      Colors.white,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM CONTENT  (labels + headline + subtitle + CTA)
// ─────────────────────────────────────────────────────────────────────────────
class _BottomContent extends StatefulWidget {
  const _BottomContent();

  @override
  State<_BottomContent> createState() => _BottomContentState();
}

class _BottomContentState extends State<_BottomContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _rise;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _rise = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Sprung.overDamped));

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _rise,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── "Duck's Stories" label ──────────────────────────────────────
            Text(
              'Duck\'s Stories',
              style: SFPro.font(
                fontSize: 14.sp,
                color: Colors.black54,
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(height: 10.h),

            // ── Headline ───────────────────────────────────────────────────
            Text(
              'Campus News\nAt Your Fingertips',
              textAlign: TextAlign.center,
              style: SFPro.font(
                fontSize: 26.sp,
                color: Colors.black,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            SizedBox(height: 16.h),

            // ── Divider with dot ───────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 50.w,
                  child: Divider(color: Colors.black26, thickness: 1),
                ),
                SizedBox(width: 6.w),
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black38, width: 1.5),
                  ),
                ),
                SizedBox(width: 6.w),
                SizedBox(
                  width: 50.w,
                  child: Divider(color: Colors.black26, thickness: 1),
                ),
              ],
            ),
            SizedBox(height: 14.h),

            // ── Subtitle ───────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Text(
                'Swipe through campus news, events, and updates from The Stute — designed for Stevens students.',
                textAlign: TextAlign.center,
                style: SFPro.font(
                  fontSize: 13.sp,
                  color: Colors.black54,
                  fontWeight: FontWeight.w400,
                  height: 1.55,
                ),
              ),
            ),
            SizedBox(height: 30.h),

            // ── CTA button ─────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: SizedBox(
                width: double.infinity,
                height: 54.h,
                child: ElevatedButton(
                  onPressed: () {
                    Get.offAllNamed('/interest');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.r),
                    ),
                  ),
                  child: Text(
                    'Explore Campus News',
                    style: SFPro.font(
                      fontSize: 15.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 36.h),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONBOARDING VIEW
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingView extends GetView<OnboardingController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ── Layer 1 : animated marquee backdrop ──────────────────────────
            const Positioned.fill(child: _AnimatedBackdrop()),

            // ── Layer 2 : bottom text + CTA (pinned to bottom) ───────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: const _BottomContent(),
            ),
          ],
        ),
      ),
    );
  }
}
