import 'dart:async';

import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/core/linked_accounts_controller.dart';
import 'package:actra/core/connected_accounts_permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

/// Auth0 wordmark in `assets/images/` (Token Vault hackathon branding).
const String kAuth0LogoAsset = 'assets/images/auth0.svg';

/// iOS system grouped background (light).
const Color _kSheetGroupedBg = Color(0xFFF080815);
// const Color _kCardSurface = Color(0xFF1C1C1C);
const Color _kLabelSecondary = Color(0x9EFFFFFF);
const Color _kSeparator = Color(0x24FFFFFF);

class _ConnectCategory {
  const _ConnectCategory({
    required this.title,
    required this.subtitle,
    required this.providerIds,
  });

  final String title;
  final String subtitle;
  final List<String> providerIds;
}

/// Groups provider ids for an Apple-style sectioned list.
List<_ConnectCategory> _categoriesForProviders(List<String> providers) {
  final set = providers.toSet();
  final out = <_ConnectCategory>[];

  if (set.contains('slack')) {
    out.add(
      const _ConnectCategory(
        title: 'Communication',
        subtitle: 'Team messaging',
        providerIds: ['slack'],
      ),
    );
  }

  final googleIds = <String>[];
  for (final id in ['google_gmail', 'google_calendar']) {
    if (set.contains(id)) googleIds.add(id);
  }
  if (googleIds.isNotEmpty) {
    out.add(
      _ConnectCategory(
        title: 'Google Workspace',
        subtitle: 'Mail & calendar',
        providerIds: googleIds,
      ),
    );
  }

  const known = {'slack', 'google_gmail', 'google_calendar'};
  final other = providers.where((p) => !known.contains(p)).toList();
  if (other.isNotEmpty) {
    out.add(
      _ConnectCategory(
        title: 'More',
        subtitle: 'Additional integrations',
        providerIds: other,
      ),
    );
  }

  return out;
}

/// [WoltModalSheetState.showPrevious] only changes the visible index — it does **not** remove
/// detail pages from the stack, so [pushPage] would accumulate [grid, slack, gmail, …].
/// Keep only the first page (the grid) before pushing a new detail, and use [popPage] for back.
void _trimModalStackToFirstPage(WoltModalSheetState sheet) {
  while (sheet.pages.length > 1) {
    sheet.popPage();
  }
}

/// Opens when [ChatController.openConnectionSheetTick] changes (backend `connections_required`).
class ConnectionSheetHost extends StatefulWidget {
  const ConnectionSheetHost({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectionSheetHost> createState() => _ConnectionSheetHostState();
}

class _ConnectionSheetHostState extends State<ConnectionSheetHost> {
  Worker? _worker;

  /// [ever] only runs when the tick *changes* after subscribe. If `connections_required`
  /// arrives in the same frame (or before our post-frame hook), we can miss 0→1 — so we
  /// dedupe by tick and always run a catch-up after attaching the worker.
  int _lastOpenedSheetTick = -1;

  void _openSheetIfNeeded(ChatController chat) {
    final tick = chat.openConnectionSheetTick.value;
    if (tick == _lastOpenedSheetTick) return;
    final providers = List<String>.from(chat.pendingProviders);
    if (providers.isEmpty) return;
    _lastOpenedSheetTick = tick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showConnectedAccountsSheet(
        context,
        providers: providers,
        reason: chat.lastConnectionReason.value,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chat = Get.find<ChatController>();
      _worker?.dispose();
      _worker = ever<int>(
        chat.openConnectionSheetTick,
        (_) => _openSheetIfNeeded(chat),
      );
      _openSheetIfNeeded(chat);
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void showConnectedAccountsSheet(
  BuildContext context, {
  required List<String> providers,
  String? reason,
}) {
  if (providers.isEmpty) return;
  if (Get.isRegistered<LinkedAccountsController>()) {
    unawaited(Get.find<LinkedAccountsController>().reloadFromBackend());
  }
  unawaited(
    WoltModalSheet.show<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      modalBarrierColor: Colors.black.withOpacity(0.6),
      enableDrag: true,
      showDragHandle: true,
      modalTypeBuilder: (_) => const WoltBottomSheetType(),
      pageListBuilder: (modalSheetContext) => [
        _gridPage(
          modalSheetContext: modalSheetContext,
          providers: providers,
          reason: reason,
        ),
      ],
    ),
  );
}

class _ProviderVisual {
  const _ProviderVisual({
    required this.label,
    required this.brandAsset,
    required this.color,
  });

  final String label;

  /// Path from [icons_plus] [Brands] (SVG via [Brand]).
  final String brandAsset;

  /// Accent for connect button / focus (brand logos stay full-color).
  final Color color;
}

String _providerRowSubtitle(String provider) {
  if (provider == 'slack') return 'Messages & channels in your workspace';
  if (provider.contains('gmail')) return 'Send mail and read threads';
  if (provider.contains('calendar')) return 'Calendar and events';
  if (provider == 'github') return 'Repositories, issues, and pull requests';
  return 'OAuth connection';
}

_ProviderVisual _providerVisual(String provider) {
  if (provider == 'slack') {
    return const _ProviderVisual(
      label: 'Slack',
      brandAsset: Brands.slack,
      color: Color(0xFF4A154B),
    );
  }
  if (provider.contains('gmail')) {
    return const _ProviderVisual(
      label: 'Gmail',
      brandAsset: Brands.gmail,
      color: Color(0xFFEA4335),
    );
  }
  if (provider.contains('calendar')) {
    return const _ProviderVisual(
      label: 'Calendar',
      brandAsset: Brands.google_calendar,
      color: Color(0xFF4285F4),
    );
  }
  if (provider == 'github') {
    return const _ProviderVisual(
      label: 'GitHub',
      brandAsset: Brands.github,
      color: Color(0xFF24292F),
    );
  }
  return _ProviderVisual(
    label: provider,
    brandAsset: Brands.google,
    color: const Color(0xFF5F6368),
  );
}

/// Renders [icons_plus] brand SVG scaled to [size].
Widget _providerBrandIcon(String brandAsset, double size) {
  return SizedBox(
    width: size,
    height: size,
    child: FittedBox(
      fit: BoxFit.contain,
      child: Brand(brandAsset, size: size),
    ),
  );
}

SliverWoltModalSheetPage _gridPage({
  required BuildContext modalSheetContext,
  required List<String> providers,
  String? reason,
}) {
  final categories = _categoriesForProviders(providers);

  return WoltModalSheetPage(
    backgroundColor: _kSheetGroupedBg,
    surfaceTintColor: Colors.transparent,
    hasTopBarLayer: true,
    isTopBarLayerAlwaysVisible: true,
    topBarTitle: Text(
      'Connections',
      style: GoogleFonts.instrumentSans(
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: Colors.white,
      ),
    ),
    trailingNavBarWidget: IconButton(
      icon: Icon(
        Icons.close_rounded,
        size: 22.sp,
        color: const Color(0xFFEBD2FF),
      ),
      onPressed: () => Navigator.of(modalSheetContext).pop(),
    ),
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 28.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connect accounts',
            style: GoogleFonts.instrumentSans(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Choose an app to link. Tokens are stored securely in Auth0 Token Vault.',
            style: GoogleFonts.instrumentSans(
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: _kLabelSecondary,
              height: 1.4,
            ),
          ),
          if (reason != null && reason.trim().isNotEmpty) ...[
            SizedBox(height: 16.h),
            _ConnectReasonBanner(text: reason.trim()),
          ],
          SizedBox(height: 20.h),
          for (var c = 0; c < categories.length; c++) ...[
            _ConnectCategorySection(
              category: categories[c],
              modalSheetContext: modalSheetContext,
            ),
            if (c < categories.length - 1) SizedBox(height: 20.h),
          ],
          SizedBox(height: 8.h),
          const _Auth0TokenVaultFooter(),
        ],
      ),
    ),
  );
}

const Color _kConnectedAccent = Color(0xFF5FD68A);

Future<void> _confirmDisconnectProvider(
  BuildContext context,
  String providerId,
) async {
  final v = _providerVisual(providerId);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1C1C24),
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Disconnect ${v.label}?',
          style: GoogleFonts.instrumentSans(
            fontSize: 17.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        content: Text(
          'You can link this account again from here anytime.',
          style: GoogleFonts.instrumentSans(
            fontSize: 14.sp,
            fontWeight: FontWeight.w400,
            color: _kLabelSecondary,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.instrumentSans(
                fontWeight: FontWeight.w600,
                color: _kLabelSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Disconnect',
              style: GoogleFonts.instrumentSans(
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF6B6B),
              ),
            ),
          ),
        ],
      );
    },
  );
  if (ok != true || !Get.isRegistered<LinkedAccountsController>()) return;
  await Get.find<LinkedAccountsController>().disconnect(providerId);
}

class _ConnectReasonBanner extends StatelessWidget {
  const _ConnectReasonBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        image: DecorationImage(
          fit: BoxFit.cover,
          opacity: 0.2,
          image: AssetImage("assets/images/chat_bubble_bg.png"),
        ),
        borderRadius: BorderRadius.circular(8.r),
        border: GradientBoxBorder(
          gradient: LinearGradient(
            begin: AlignmentGeometry.topLeft,
            end: AlignmentGeometry.bottomRight,
            colors: [
              Color(0xFFEDD9FF).withOpacity(0.6),
              Colors.white10,
              Color(0xFFC887FF).withOpacity(0.6),
            ],
          ),
          width: 0.7,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20.sp,
              color: const Color(0xFFF3E5FF),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.instrumentSans(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFF3E5FF),
                  // height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectCategorySection extends StatelessWidget {
  const _ConnectCategorySection({
    required this.category,
    required this.modalSheetContext,
  });

  final _ConnectCategory category;
  final BuildContext modalSheetContext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.title.toUpperCase(),
                style: GoogleFonts.instrumentSans(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: _kLabelSecondary,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                category.subtitle,
                style: GoogleFonts.instrumentSans(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w400,
                  color: _kLabelSecondary.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0C0D18), // 0%
                Color(0xFF10101E), // 69%
                Color(0xFF1A1B24), // 100%
              ],
              stops: [0.0, 0.69, 1.0],
            ),
            border: GradientBoxBorder(
              gradient: LinearGradient(
                begin: AlignmentGeometry.topLeft,
                end: AlignmentGeometry.bottomRight,
                colors: [
                  Color(0xFFEDD9FF).withOpacity(0.6),
                  Colors.white10,
                  Color(0xFFC887FF).withOpacity(0.6),
                ],
              ),
              width: 0.7,
            ),
            // color: _kCardSurface,
            borderRadius: BorderRadius.circular(12),
            // boxShadow: [
            //   BoxShadow(
            //     color: Colors.black.withValues(alpha: 0.04),
            //     blurRadius: 8,
            //     offset: const Offset(0, 2),
            //   ),
            // ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                for (var i = 0; i < category.providerIds.length; i++)
                  _ConnectProviderRow(
                    providerId: category.providerIds[i],
                    modalSheetContext: modalSheetContext,
                    showDivider: i < category.providerIds.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectProviderRow extends StatelessWidget {
  const _ConnectProviderRow({
    required this.providerId,
    required this.modalSheetContext,
    required this.showDivider,
  });

  final String providerId;
  final BuildContext modalSheetContext;
  final bool showDivider;

  void _openDetail() {
    final sheet = WoltModalSheet.of(modalSheetContext);
    _trimModalStackToFirstPage(sheet);
    sheet.pushPage(
      _detailPage(
        modalSheetContext: modalSheetContext,
        provider: providerId,
      ),
    );
  }

  Widget _buildRow(BuildContext context, {required bool isLinked}) {
    final v = _providerVisual(providerId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLinked ? null : _openDetail,
            onLongPress: isLinked
                ? () => unawaited(_confirmDisconnectProvider(context, providerId))
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isLinked ? Colors.white.withValues(alpha: 0.03) : null,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF252525).withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: const GradientBoxBorder(
                          gradient: LinearGradient(
                            begin: AlignmentGeometry.topLeft,
                            end: AlignmentGeometry.bottomRight,
                            colors: [
                              Color(0xFFEDD9FF),
                              Colors.white10,
                              Color(0xFFC887FF),
                            ],
                          ),
                          width: 0.7,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: _providerBrandIcon(v.brandAsset, 28.sp),
                      ),
                    ),
                    SizedBox(width: 14.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.label,
                            style: GoogleFonts.instrumentSans(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.32,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            _providerRowSubtitle(providerId),
                            style: GoogleFonts.instrumentSans(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w400,
                              color: _kLabelSecondary,
                            ),
                          ),
                          if (isLinked) ...[
                            SizedBox(height: 6.h),
                            Row(
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: _kConnectedAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Text(
                                  'Connected',
                                  style: GoogleFonts.instrumentSans(
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                    color: _kConnectedAccent.withValues(alpha: 0.92),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isLinked)
                      Tooltip(
                        message: 'Disconnect',
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints.tight(Size(36.w, 36.h)),
                          icon: Icon(
                            Icons.link_off_rounded,
                            color: const Color(0xFFEBD2FF).withValues(alpha: 0.75),
                            size: 20.sp,
                          ),
                          onPressed: () =>
                              unawaited(_confirmDisconnectProvider(context, providerId)),
                        ),
                      ),
                    if (!isLinked)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: const Color(0xFFC7C7CC),
                        size: 22.sp,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 0.5, color: _kSeparator, indent: 72.w),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Get.isRegistered<LinkedAccountsController>()) {
      return Obx(() {
        final linked = Get.find<LinkedAccountsController>().linkedProviders;
        final isLinked = linked.contains(providerId);
        return _buildRow(context, isLinked: isLinked);
      });
    }
    return _buildRow(context, isLinked: false);
  }
}

SliverWoltModalSheetPage _detailPage({
  required BuildContext modalSheetContext,
  required String provider,
}) {
  final v = _providerVisual(provider);
  final bullets = ConnectedAccountsPermissions.bulletsForProvider(provider);

  return WoltModalSheetPage(
    id: 'detail_$provider',
    backgroundColor: _kSheetGroupedBg,
    surfaceTintColor: Colors.transparent,
    hasTopBarLayer: true,
    isTopBarLayerAlwaysVisible: true,
    leadingNavBarWidget: IconButton(
      icon: Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 18.sp,
        color: const Color(0xFFEBD2FF),
      ),
      onPressed: () {
        final sheet = WoltModalSheet.of(modalSheetContext);
        sheet.popPage();
      },
    ),
    topBarTitle: Text(
      v.label,
      style: GoogleFonts.instrumentSans(
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: Colors.white,
      ),
    ),
    trailingNavBarWidget: IconButton(
      icon: Icon(
        Icons.close_rounded,
        size: 22.sp,
        color: const Color(0xFFEBD2FF),
      ),
      onPressed: () => Navigator.of(modalSheetContext).pop(),
    ),
    stickyActionBar: DecoratedBox(
      decoration: const BoxDecoration(
        color: _kSheetGroupedBg,
        border: Border(top: BorderSide(color: Color(0x1F000000))),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 7.h),
        child: _ConnectBar(provider: provider, visual: v),
      ),
    ),
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0C0D18), // 0%
                    Color(0xFF10101E), // 69%
                    Color(0xFF1A1B24), // 100%
                  ],
                  stops: [0.0, 0.69, 1.0],
                ),
                border: const GradientBoxBorder(
                  gradient: LinearGradient(
                    begin: AlignmentGeometry.topLeft,
                    end: AlignmentGeometry.bottomRight,
                    colors: [
                      Color(0xFFEDD9FF),
                      Colors.white10,
                      Color(0xFFC887FF),
                    ],
                  ),
                  width: 0.7,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: EdgeInsets.all(20.w),
                child: _providerBrandIcon(v.brandAsset, 30.w),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            _providerRowSubtitle(provider),
            textAlign: TextAlign.center,
            style: GoogleFonts.instrumentSans(
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: _kLabelSecondary,
            ),
          ),
          SizedBox(height: 24.h),
          Padding(
            padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
            child: Text(
              'PERMISSION ACCESS',
              style: GoogleFonts.instrumentSans(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: _kLabelSecondary,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0C0D18), // 0%
                  Color(0xFF10101E), // 69%
                  Color(0xFF1A1B24), // 100%
                ],
                stops: [0.0, 0.69, 1.0],
              ),
              border: const GradientBoxBorder(
                gradient: LinearGradient(
                  begin: AlignmentGeometry.topLeft,
                  end: AlignmentGeometry.bottomRight,
                  colors: [
                    Color(0xFFEDD9FF),
                    Colors.white10,
                    Color(0xFFC887FF),
                  ],
                ),
                width: 0.7,
              ),
              borderRadius: BorderRadius.circular(12),
              // boxShadow: [
              //   BoxShadow(
              //     color: Colors.black.withValues(alpha: 0.04),
              //     blurRadius: 8,
              //     offset: const Offset(0, 2),
              //   ),
              // ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
              child: Column(
                children: [
                  for (var i = 0; i < bullets.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 0.5, color: _kSeparator),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 6.h),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0x5CEBD2FF),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bullets[i].title,
                                  style: GoogleFonts.instrumentSans(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.24,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  bullets[i].description,
                                  style: GoogleFonts.instrumentSans(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w400,
                                    color: _kLabelSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 24.h),
          const _Auth0TokenVaultFooter(),
        ],
      ),
    ),
  );
}

/// Auth0 + Token Vault trust line for Connected Accounts (My Account API → Token Vault).
class _Auth0TokenVaultFooter extends StatelessWidget {
  const _Auth0TokenVaultFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 14.h),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
        SizedBox(height: 14.h),
        Center(
          child: SvgPicture.asset(
            kAuth0LogoAsset,
            height: 22.h,
            color: Colors.white,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          'Secured with Auth0 Token Vault',
          textAlign: TextAlign.center,
          style: GoogleFonts.instrumentSans(
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          'OAuth tokens for linked accounts are stored per user in your Auth0 tenant’s Token Vault.',
          textAlign: TextAlign.center,
          style: GoogleFonts.instrumentSans(
            fontSize: 10.sp,
            fontWeight: FontWeight.w400,
            color: Colors.white.withOpacity(0.6),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ConnectBar extends StatefulWidget {
  const _ConnectBar({required this.provider, required this.visual});

  final String provider;
  final _ProviderVisual visual;

  @override
  State<_ConnectBar> createState() => _ConnectBarState();
}

class _ConnectBarState extends State<_ConnectBar> {
  bool _loading = false;

  Future<void> _onConnect() async {
    if (_loading) return;
    setState(() => _loading = true);
    final chat = Get.find<ChatController>();
    final ok = await chat.connectProvider(
      widget.provider,
      suppressSuccessSnack: true,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _loading = false);
      return;
    }
    Navigator.of(context).pop();
    chat.resolveConnectionPromptForProvider(widget.provider);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40.h,
      child: FilledButton(
        onPressed: _loading ? null : _onConnect,
        style: FilledButton.styleFrom(
          backgroundColor: widget.visual.color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: widget.visual.color.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _loading
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Connect ${widget.visual.label}',
                    style: GoogleFonts.instrumentSans(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  10.horizontalSpace,
                  Icon(EvaIcons.link_2_outline),
                ],
              ),
      ),
    );
  }
}
