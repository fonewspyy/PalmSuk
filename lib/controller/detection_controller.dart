import 'package:camera/camera.dart';
import 'package:get/get.dart';

class DetectionController extends GetxController {
  late CameraController cameraController;
  Rx<bool> isInitialized = Rx(false);

  @override
  void onInit() async {
    // await loadDataModel();
    await initializeCamera();
    super.onInit();
  }

  @override
  void onClose() async {
    super.onClose();
  }
  // Future loadDataModel() async{
  //   await Tflite.loadModel(
  //     model:"assets/model/model.tflite"
  //     labels:"assets/model/label.txt"
  //   );
  // }

  Future initializeCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await cameraController.initialize();
    isInitialized.value = true;
  }
}
