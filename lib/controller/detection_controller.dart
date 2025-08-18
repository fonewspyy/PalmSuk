import 'package:camera/camera.dart';
import 'package:get/get.dart';
import '../services/yolo_v8_nms.dart';
import 'package:flutter/foundation.dart';

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

  final _yolo = YoloV8Nms();
  final double minConf = 0.30;
  
  @override
  void onInit() async {
    await _yolo.load(
      modelAsset: "assets/models/best_float16.tflite",
      labelsAsset: "assets/models/palm.txt",
    );
    super.onInit();
  }

  @override
  void onClose() {
    if (cameraController.value.isStreamingImages) {
      cameraController.stopImageStream();
    }
    cameraController.dispose();
    _yolo.close();
    super.onClose();
  }

  Future initializeCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420, // สำคัญ
    );
    await cameraController.initialize();
    isInitialized.value = true;
  }

  Future<void> _onStream(CameraImage img) async {
    if (isprocessing || !_yolo.isReady) return;
    isprocessing = true;

    try {
      imageHeight.value = img.height.toDouble();
      imageWidth.value = img.width.toDouble();

      final dets = await _yolo.runOnFrame(img);
      recognitions.value = dets;

      // 👇 LOG ชัด ๆ
      if (kDebugMode) {
        if (dets.isEmpty) {
          print('[YOLO] no detections');
        } else {
          final top = dets.first;
          print('[YOLO] N=${dets.length} '
                'top=${top["detectedClass"]} '
                'conf=${(top["confidenceInClass"] as double).toStringAsFixed(2)} '
                'rect=${top["rect"]}');
        }
      }

      // นับผล
      ripeCount.value = 0;
      unripeCount.value = 0;
      for (final re in dets) {
        final cls = (re["detectedClass"] as String).toLowerCase();
        final conf = (re["confidenceInClass"] as num).toDouble();
        if (conf >= minConf) {
          if (cls.contains("ripe")) {
            ripeCount.value++;
          } else if (cls.contains("unripe")) {
            unripeCount.value++;
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('[YOLO][ERR] $e\n$st');
      }
    } finally {
      isprocessing = false;
    }
  }

  Future<void> toggleCamera() async {
    if (!isInitialized.value) {
      await initializeCamera();
      isCameraRunning.value = true;
      try {
        await cameraController.startImageStream(_onStream);
        isStreaming.value = true;
      } catch (e) {
        isCameraRunning.value = false;
        rethrow;
      }
    } else {
      // ปิดกล้อง
      if (isStreaming.value) {
        await cameraController.stopImageStream();
        isStreaming.value = false;
      }
      await cameraController.dispose();
      isInitialized.value = false;
      isCameraRunning.value = false;
    }
  }

}
