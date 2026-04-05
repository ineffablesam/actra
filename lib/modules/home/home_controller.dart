import 'package:actra/routes/app_pages.dart';
import 'package:get/get.dart';

class HomeController extends GetxController {
  final RxBool homeCompleted = false.obs;

  final RxBool isLoading = false.obs;

  final RxList<String> selectedInterests = <String>[].obs;

  static const int minSelection = 4;

  void toggleInterest(String id) {
    if (selectedInterests.contains(id)) {
      selectedInterests.remove(id);
    } else {
      selectedInterests.add(id);
    }
  }

  bool isSelected(String id) {
    return selectedInterests.contains(id);
  }

  int get selectedCount => selectedInterests.length;

  void goToInterest() {
    Get.offAllNamed(Routes.INTREST);
  }

  Future<void> finishHomeFlow() async {
    isLoading.value = true;

    await Future.delayed(const Duration(milliseconds: 400));

    homeCompleted.value = true;

    isLoading.value = false;

    Get.offAllNamed(Routes.LAYOUT);
  }
}
