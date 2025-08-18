import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter_tflite/flutter_tflite.dart';
import 'package:get/get.dart';

class DetectionController extends GetxController {
  RxBool isStreaming = false.obs;
  late CameraController cameraController;
  Rx<bool> isInitialized = Rx(false);
  RxString result = "".obs;
  bool isprocessing = false;
  RxList recognitions = [].obs;

  RxDouble imageHeight = 0.0.obs;
  RxDouble imageWidth = 0.0.obs;

  RxInt ripeCount = 0.obs;
  RxInt unripeCount = 0.obs;
  RxBool isCameraRunning = false.obs;

  @override
  void onInit() async {
    await loadDataModel();
    // await initializeCamera();
    super.onInit();
  }

  @override
  void onClose() {
    if (cameraController.value.isStreamingImages) {
      cameraController.stopImageStream();
    }
    cameraController.dispose();
    super.onClose();
  }

  Future loadDataModel() async {
    await Tflite.loadModel(
      model: "assets/models/palm.tflite",
      labels: "assets/models/palm.txt",
    );
  }

  Future initializeCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await cameraController.initialize();
    isInitialized.value = true;
    // cameraController.startImageStream(ssDrunModeOnStreamFram);
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

      

      // Reset count
      ripeCount.value = 0;
      unripeCount.value = 0;

      // // 🔽 วนลูปเพื่อเช็กว่าตรวจเจอ class ไหน
      for (var re in recognitions) {
        if (re["confidenceInClass"] >= 0.5) {
          if (re["detectedClass"] == "ripe") {
            ripeCount.value++;
          } else if (re["detectedClass"] == "unripe") {
            unripeCount.value++;
          }
        }
      }

      // print(recognitions.value);
    } catch (e) {
    } finally {
      isprocessing = false;
    }
  }

  // ปุ่ม SEARCH เปิด-ปิดกล้อง
  Future<void> toggleCamera() async {
    if (isInitialized.value) {
      // ปิดกล้อง
      if (isStreaming.value) {
        try {
          await cameraController.stopImageStream();
          isStreaming.value = false;
        } catch (e) {
          print("⚠️ stopImageStream ล้มเหลว: $e");
        }
      }

      await cameraController.dispose();
      isInitialized.value = false;
      isCameraRunning.value = false;
    } else {
      // เปิดกล้อง
      final cameras = await availableCameras();
      cameraController = CameraController(cameras[0], ResolutionPreset.medium);
      await cameraController.initialize();
      isInitialized.value = true;
      isCameraRunning.value = true;

      try {
        await cameraController.startImageStream(ssDrunModeOnStreamFram);
        isStreaming.value = true;
      } catch (e) {
        print("⚠️ startImageStream ล้มเหลว: $e");
      }
    }
  }

  // takePicture() async {
  //   try {
  //     var file = await cameraController.takePicture();
  //     File image = File(file.path);
  //     if (isprocessing) return;
  //     isprocessing = true;
  //     await Future.delayed(const Duration(seconds: 1));
  //     result.value = '';
  //     var Recognitions = await Tflite.detectObjectOnImage(
  //       path: image.path,
  //       numResultsPerClass: 1,
  //     );
  //     for (var recognition in Recognitions!) {
  //       result.value +=
  //           "${recognition["detectedClass"]} - ${recognition["confidenceInClass"]} \n";
  //     }
  //   } catch (e) {
  //   } finally {
  //     isprocessing = false;
  //   }
  // }
}