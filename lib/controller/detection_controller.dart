import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_tflite/flutter_tflite.dart';
import 'package:get/get.dart';

class DetectionController extends GetxController {
  late CameraController cameraController;
  Rx<bool> isInitialized = Rx(false);
  RxString result = "".obs;
  bool isprocessing = false;
  RxList recognitions = [].obs;

  RxDouble imageHeight = 0.0.obs;
  RxDouble imageWidth = 0.0.obs;

  @override
  void onInit() async {
    await loadDataModel();
    await initializeCamera();
    super.onInit();
  }

  @override
  void onClose() async {
    super.onClose();
  }

  Future loadDataModel() async {
    await Tflite.loadModel(
      model: "assets/models/ssd_mobilenet.tflite",
      labels: "assets/models/ssd_mobilenet.txt",
    );
  }

  Future initializeCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await cameraController.initialize();
    isInitialized.value = true;
    if (Get.arguments['type'] == "streaming") {
      cameraController.startImageStream(ssDrunModeOnStreamFram);
    }
  }

  ssDrunModeOnStreamFram(CameraImage img) async {
    if (isprocessing) return;
    isprocessing = true;
    await Future.delayed(const Duration(microseconds: 500));
    result.value = "";
    try {
      imageHeight.value = img.height.toDouble();
      imageWidth.value = img.width.toDouble();
      recognitions.value = (await Tflite.detectObjectOnFrame(
        bytesList: img.planes.map((plan) {
          return plan.bytes;
        }).toList(),
        model: 'SSDMobileNet',
        imageHeight: img.height,
        imageWidth: img.width,
        imageMean: 127.5,
        imageStd: 127.5,
        rotation: 90,
        numResultsPerClass: 2,
        threshold: 0.1,
        asynch: true,
      ))!;
      print(recognitions.value);
    } catch (e) {
    } finally {
      isprocessing = false;
    }
  }

  takePicture() async {
    try {
      var file = await cameraController.takePicture();
      File image = File(file.path);
      if (isprocessing) return;
      isprocessing = true;
      await Future.delayed(const Duration(seconds: 1));
      result.value = '';
      var Recognitions = await Tflite.detectObjectOnImage(
        path: image.path,
        numResultsPerClass: 1,
      );
      for (var recognition in Recognitions!) {
        result.value +=
            "${recognition["detectedClass"]} - ${recognition["confidenceInClass"]} \n";
      }
    } catch (e) {
    } finally {
      isprocessing = false;
    }
  }
}
