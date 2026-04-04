import 'package:actra/core/auth0_my_account_linking.dart';
import 'package:actra/core/auth0_service.dart';
import 'package:actra/core/auth_session_service.dart';
import 'package:actra/core/connected_accounts_service.dart';
import 'package:actra/routes/app_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_setup.dart';

import 'modules/shader/shader_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Get.put(AuthSessionService(), permanent: true);
  await Get.find<AuthSessionService>().hydrateFromStorage();
  Get.put(Auth0Service(), permanent: true);
  Get.put(Auth0MyAccountLinking(), permanent: true);
  Get.put(ConnectedAccountsService(), permanent: true);
  Get.put(ShaderController(), permanent: true);
  await LiquidGlassWidgets.initialize();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final refreshRateControl = FlutterRefreshRateControl();

  try {
    bool success = await refreshRateControl.requestHighRefreshRate();
    if (success) {
      print('High refresh rate enabled');
    } else {
      print('Failed to enable high refresh rate');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error: $e');
    }
  }

  runApp(LiquidGlassWidgets.wrap(const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return GetMaterialApp(
          defaultTransition: Transition.fadeIn,
          transitionDuration: Duration(milliseconds: 550),
          debugShowCheckedModeBanner: false,
          title: 'The Stute',
          initialRoute: AppPages.INITIAL,
          getPages: AppPages.routes,
        );
      },
    );
  }
}
