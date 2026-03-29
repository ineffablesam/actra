import 'package:actra/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final _refreshRateControl = FlutterRefreshRateControl();

  try {
    bool success = await _refreshRateControl.requestHighRefreshRate();
    if (success) {
      print('High refresh rate enabled');
    } else {
      print('Failed to enable high refresh rate');
    }
  } catch (e) {
    print('Error: $e');
  }

  runApp(const MyApp());
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
