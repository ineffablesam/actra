import 'package:actra/modules/home/home_binding.dart';
import 'package:actra/modules/home/home_view.dart';
import 'package:actra/modules/layout/views/layout_view.dart';
import 'package:actra/modules/onboarding/interest_view.dart';
import 'package:get/get.dart';

import '../modules/splash/splash_binding.dart';
import '../modules/splash/splash_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const INITIAL = Routes.SPLASH;
  static const HOME = Routes.HOME;
  static const LAYOUT = Routes.LAYOUT;

  static final routes = [
    GetPage(
      name: _Paths.SPLASH,
      page: () => const SplashView(),
      binding: SplashBinding(),
    ),
    GetPage(
      name: _Paths.HOME,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: _Paths.INTREST,
      page: () => InterestView(),
      binding: HomeBinding(),
    ),
    GetPage(name: _Paths.LAYOUT, page: () => const LayoutView()),
  ];
}
