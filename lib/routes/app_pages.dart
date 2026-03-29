import 'package:actra/modules/layout/views/layout_view.dart';
import 'package:actra/modules/onboarding/interest_view.dart';
import 'package:actra/modules/onboarding/onboarding_binding.dart';
import 'package:actra/modules/onboarding/onboarding_view.dart';
import 'package:get/get.dart';

import '../modules/splash/splash_binding.dart';
import '../modules/splash/splash_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.SPLASH;
  static const ONBOARDING = Routes.ONBOARDING;
  static const LAYOUT = Routes.LAYOUT;

  static final routes = [
    GetPage(
      name: _Paths.SPLASH,
      page: () => const SplashView(),
      binding: SplashBinding(),
    ),
    GetPage(
      name: _Paths.ONBOARDING,
      page: () => const OnboardingView(),
      binding: OnboardingBinding(),
    ),
    GetPage(
      name: _Paths.INTREST,
      page: () => InterestView(),
      binding: OnboardingBinding(),
    ),
    GetPage(name: _Paths.LAYOUT, page: () => const LayoutView()),
  ];
}
