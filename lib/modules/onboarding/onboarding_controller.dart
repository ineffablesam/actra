import 'package:get/get.dart';

class OnboardingController extends GetxController {
  /// onboarding completed
  final RxBool onboardingCompleted = false.obs;

  /// loading state if needed later
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

  /// continue button
  void goToInterest() {
    Get.offAllNamed('/interest');
  }

  /// finish onboarding
  Future<void> finishOnboarding() async {
    isLoading.value = true;

    await Future.delayed(const Duration(milliseconds: 400));

    onboardingCompleted.value = true;

    isLoading.value = false;

    Get.offAllNamed('/layout');
  }
}
