import 'package:actra/chat/controllers/chat_controller.dart';
import 'package:actra/chat/services/audio_service.dart';
import 'package:actra/chat/services/websocket_service.dart';
import 'package:actra/core/linked_accounts_controller.dart';
import 'package:actra/modules/audio/audio_controller.dart';
import 'package:actra/modules/home/home_controller.dart';
import 'package:get/get.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HomeController>(() => HomeController());
    Get.lazyPut<LinkedAccountsController>(() => LinkedAccountsController());
    Get.lazyPut<AudioController>(() => AudioController());
    Get.lazyPut<WebSocketService>(() => WebSocketService(), fenix: true);
    Get.lazyPut<AudioService>(() => AudioService(), fenix: true);
    Get.lazyPut<ChatController>(() => ChatController(), fenix: true);
  }
}
