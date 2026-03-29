import 'dart:async';

import 'package:actra/modules/onboarding/onboarding_controller.dart';
import 'package:actra/utils/colors.dart';
import 'package:actra/utils/sf_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:sprung/sprung.dart';

// ─────────────────────────────────────────────────────────────────────────────
// INTEREST CATEGORY DATA
// ─────────────────────────────────────────────────────────────────────────────
class InterestCategory {
  final String id;
  final String title;
  final String imagePath;
  final IconData icon;

  const InterestCategory({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.icon,
  });
}

const List<InterestCategory> _categories = [
  InterestCategory(
    id: 'sports',
    title: 'Sports',
    imagePath: 'assets/images/interest_sports.webp',
    icon: Icons.sports_basketball,
  ),
  InterestCategory(
    id: 'technology',
    title: 'Technology',
    imagePath: 'assets/images/interest_tech.jpg',
    icon: Icons.computer,
  ),
  InterestCategory(
    id: 'arts',
    title: 'Arts & Culture',
    imagePath: 'assets/images/interest_arts.jpg',
    icon: Icons.palette,
  ),
  InterestCategory(
    id: 'campus_life',
    title: 'Campus Life',
    imagePath: 'assets/images/interest_campus.jpg',
    icon: Icons.school,
  ),
  InterestCategory(
    id: 'entertainment',
    title: 'Entertainment',
    imagePath: 'assets/images/interest_entertainment.png',
    icon: Icons.movie,
  ),
  InterestCategory(
    id: 'science',
    title: 'Science',
    imagePath: 'assets/images/interest_science.png',
    icon: Icons.science,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// INTEREST CARD (with animated selection states)
// ─────────────────────────────────────────────────────────────────────────────
class _InterestCard extends StatefulWidget {
  final InterestCategory category;
  final bool isSelected;
  final VoidCallback onTap;
  final int index;

  const _InterestCard({
    required this.category,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  @override
  State<_InterestCard> createState() => _InterestCardState();
}

class _InterestCardState extends State<_InterestCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();

    // Entry animation
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _entryFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));

    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Sprung.overDamped));

    // Staggered entry
    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
      if (mounted) _entryCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Sprung.overDamped,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: widget.isSelected
                    ? const Color(0xFF1A1A1A)
                    : Colors.grey.shade300,
                width: widget.isSelected ? 2.5 : 1.5,
              ),
              color: widget.isSelected
                  ? const Color(0xFF1A1A1A).withOpacity(0.05)
                  : Colors.white,
              // boxShadow: widget.isSelected
              //     ? [
              //         BoxShadow(
              //           color: const Color(0xFF1A1A1A).withOpacity(0.1),
              //           blurRadius: 12,
              //           offset: const Offset(0, 4),
              //         ),
              //       ]
              //     : [
              //         BoxShadow(
              //           color: Colors.black.withOpacity(0.04),
              //           blurRadius: 8,
              //           offset: const Offset(0, 2),
              //         ),
              //       ],
            ),
            child: Stack(
              children: [
                // Background Image
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14.r),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Image with fallback
                        Image.asset(
                          widget.category.imagePath,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.grey.shade200,
                                  Colors.grey.shade300,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                widget.category.icon,
                                size: 48.sp,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        // Gradient overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.1),
                                Colors.black.withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: EdgeInsets.all(14.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Title
                      Text(
                        widget.category.title,
                        style: SFPro.font(
                          fontSize: 15.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Checkmark for selected state
                if (widget.isSelected)
                  Positioned(
                    top: 10.w,
                    right: 10.w,
                    child: AnimatedScale(
                      scale: widget.isSelected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Sprung.overDamped,
                      child: Container(
                        width: 28.w,
                        height: 28.w,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18.sp,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _HeaderSection extends StatefulWidget {
  const _HeaderSection();

  @override
  State<_HeaderSection> createState() => _HeaderSectionState();
}

class _HeaderSectionState extends State<_HeaderSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

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

    _slide = Tween<Offset>(
      begin: const Offset(0, -0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Sprung.overDamped));

    Future.delayed(const Duration(milliseconds: 100), () {
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
        position: _slide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            Text(
              'Personalize Your Feed',
              style: SFPro.font(
                fontSize: 14.sp,
                color: Colors.black54,
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(height: 12.h),

            // Main headline
            Text(
              'What interests\nyou?',
              style: SFPro.font(
                fontSize: 32.sp,
                color: Colors.black,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            SizedBox(height: 14.h),

            // Subtitle
            Text(
              'Select at least 4 categories to customize your campus news feed.',
              style: SFPro.font(
                fontSize: 14.sp,
                color: Colors.black54,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKY BOTTOM BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _StickyBottomButton extends StatefulWidget {
  final int selectedCount;
  final VoidCallback onContinue;

  const _StickyBottomButton({
    required this.selectedCount,
    required this.onContinue,
  });

  @override
  State<_StickyBottomButton> createState() => _StickyBottomButtonState();
}

class _StickyBottomButtonState extends State<_StickyBottomButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Sprung.overDamped));

    Future.delayed(const Duration(milliseconds: 400), () {
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
    final isEnabled = widget.selectedCount >= 4;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: EdgeInsets.only(
            left: 24.w,
            right: 24.w,
            top: 10.h,
            bottom: 36.h,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Counter text
              AnimatedOpacity(
                opacity: widget.selectedCount > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: Text(
                    '${widget.selectedCount} selected ${isEnabled ? '✓' : '(${4 - widget.selectedCount} more needed)'}',
                    style: SFPro.font(
                      fontSize: 13.sp,
                      color: isEnabled ? Colors.green.shade700 : Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 54.h,
                child: ElevatedButton(
                  onPressed: isEnabled ? widget.onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.r),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: SFPro.font(
                      fontSize: 15.sp,
                      color: isEnabled ? Colors.white : Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN INTEREST VIEW
// ─────────────────────────────────────────────────────────────────────────────
class InterestView extends GetView<OnboardingController> {
  const InterestView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<OnboardingController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              /// Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 120.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HeaderSection(),
                      SizedBox(height: 24.h),

                      /// Grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _categories.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 14.w,
                          mainAxisSpacing: 14.h,
                        ),
                        itemBuilder: (context, index) {
                          final category = _categories[index];

                          /// Each card listens individually
                          return Obx(() {
                            final isSelected = controller.selectedInterests
                                .contains(category.id);

                            return _InterestCard(
                              category: category,
                              index: index,
                              isSelected: isSelected,
                              onTap: () =>
                                  controller.toggleInterest(category.id),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              /// Bottom Button
              Obx(() {
                return _StickyBottomButton(
                  selectedCount: controller.selectedCount,
                  onContinue: controller.finishOnboarding,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
