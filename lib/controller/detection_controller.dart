import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; // For debugPrint
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img_lib; // Import image package for processing
import 'dart:math' as math; // For math.max and math.min

// เพิ่ม Imports สำหรับบันทึกภาพ
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver_plus/gallery_saver.dart'; // ใช้ gallery_saver_plus
import 'dart:io' as io; // Alias dart:io to avoid conflict with Image if any

class DetectionController extends GetxController {
  // Camera
  RxBool isStreaming = false.obs;
  late CameraController cameraController;
  Rx<bool> isInitialized = Rx(false);
  RxBool isCameraRunning = false.obs;

  // Inference
  bool _busy = false;
  Interpreter? interpreter;
  TensorType? _inputType; // เปลี่ยนจาก TfLiteType? เป็น TensorType?
  int? inW, inH; // model input (w, h)
  int? valuesPerDet, numDet; // 6, 8400 (หรือ 8400, 6)
  bool _layoutCHW = false; // true เมื่อ output เป็น [1, 6, 8400]
  List<String> labels = [];

  // Results/state
  RxList recognitions = [].obs;
  RxInt ripeCount = 0.obs;
  RxInt unripeCount = 0.obs;
  RxDouble imgW = 0.0.obs;
  RxDouble imgH = 0.0.obs;

  // Save control
  bool _saveNextFrame = false; // save เฟรมถัดไปเมื่อสั่งเท่านั้น

  @override
  Future<void> onInit() async {
    await _loadModelAndLabels();
    super.onInit();
  }

  @override
  Future<void> onClose() async {
    try {
      if (isInitialized.value && cameraController.value.isStreamingImages) {
        await cameraController.stopImageStream();
      }
    } catch (_) {}
    if (isInitialized.value) {
      await cameraController.dispose();
    }
    interpreter?.close();
    super.onClose();
  }

  /// ========== MODEL LOADING ==========
  Future<void> _loadModelAndLabels() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      // GPU delegate ถูกคอมเมนต์ไปแล้ว ตามที่เราได้แก้ไข
      
      interpreter = await Interpreter.fromAsset(
        'assets/models/palm.tflite',
        options: options,
      );
      debugPrint('✅ TFLite model loaded');

      // labels
      final labelStr = await rootBundle.loadString('assets/models/palm.txt');
      labels = labelStr
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      debugPrint('✅ Labels: $labels');

      // input tensor
      final inTensor = interpreter!.getInputTensors().first;
      _inputType = inTensor.type; 
      final inShape = inTensor.shape; // [1, h, w, 3]
      if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
        throw Exception('Unexpected input shape: $inShape (expect [1,h,w,3])');
      }
      inH = inShape[1];
      inW = inShape[2];
      debugPrint('📥 Input: ${inW}x${inH}, type=$_inputType');

      // output tensor
      final outTensor = interpreter!.getOutputTensors().first;
      final outShape = outTensor.shape; // either [1,6,8400] or [1,8400,6]
      if (outShape.length != 3 || outShape[0] != 1) {
        throw Exception('Unexpected output shape: $outShape');
      }
      if (outShape[1] == 6) {
        // [1, 6, 8400]
        _layoutCHW = true;
        valuesPerDet = outShape[1]; // 6
        numDet = outShape[2]; // 8400
      } else if (outShape[2] == 6) {
        // [1, 8400, 6]
        _layoutCHW = false;
        valuesPerDet = outShape[2]; // 6
        numDet = outShape[1]; // 8400
      } else {
        throw Exception('Cannot find 6-dim per detection in output: $outShape');
      }
      debugPrint(
        '📤 Output: layoutCHW=$_layoutCHW, values=$valuesPerDet, num=$numDet',
      );
    } catch (e) {
      debugPrint('❌ Load model/labels failed: $e');
      interpreter = null;
    }
  }

  /// ========== CAMERA ==========
  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    // กล้องหลังมักอยู่ index 0
    cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await cameraController.initialize();
    isInitialized.value = true;
  }

  Future<void> toggleCamera() async {
    if (!isInitialized.value) {
      await initializeCamera();
      isCameraRunning.value = true;
      await _startStream();
    } else {
      await _stopStream();
      await cameraController.dispose();
      isInitialized.value = false;
      isCameraRunning.value = false;
    }
  }

  Future<void> _startStream() async {
    if (interpreter == null) {
      debugPrint('⚠️ Interpreter not ready');
      return;
    }
    try {
      await cameraController.startImageStream(_onStreamFrame);
      isStreaming.value = true;
    } catch (e) {
      debugPrint('⚠️ startImageStream failed: $e');
    }
  }

  Future<void> _stopStream() async {
    try {
      if (cameraController.value.isStreamingImages) {
        await cameraController.stopImageStream();
      }
    } catch (e) {
      debugPrint('⚠️ stopImageStream failed: $e');
    }
    isStreaming.value = false;
  }

  /// เรียกจาก UI เมื่ออยากบันทึกเฟรมถัดไป
  void saveNextFrame() {
    _saveNextFrame = true;
  }

  /// ========== STREAM CALLBACK ==========
  Future<void> _onStreamFrame(CameraImage img) async {
    if (_busy ||
        interpreter == null ||
        inW == null ||
        inH == null ||
        numDet == null)
      return;
    _busy = true;

    recognitions.clear();
    ripeCount.value = 0;
    unripeCount.value = 0;

    try {
      imgW.value = img.width.toDouble();
      imgH.value = img.height.toDouble();

      // 1) แปลง YUV420 -> RGB (ช้าที่สุดในโค้ดนี้ ถ้าจะลื่นมากให้ย้ายไป native/FFI)
      final rgb = _yuv420ToImage(img);

      // 2) resize ให้ตรงกับ input model
      final resized = img_lib.copyResize(rgb, width: inW!, height: inH!);

      // 3) เตรียมอินพุตตามชนิดเทนเซอร์
      final input = _makeInput(resized); // ตอนนี้ _makeInput จะคืนค่าเป็น List 4 มิติ

      // 4) เตรียมเอาต์พุต
      // เลือกโครงสร้างให้ตรง layout
      Object output;
      if (_layoutCHW) {
        // [1, 6, 8400]
        output = List.generate(
          1,
          (_) => List.generate(6, (_) => List<double>.filled(numDet!, 0.0)),
        );
      } else {
        // [1, 8400, 6]
        output = List.generate(
          1,
          (_) => List.generate(numDet!, (_) => List<double>.filled(6, 0.0)),
        );
      }

      // 5) รัน
      interpreter!.run(input, output); // input จะเป็น List 4 มิติแล้ว

      // 6) แปลงผลลัพธ์ + NMS เล็กน้อย
      final dets = _parseDetections(output);

      final filtered = _nms(
        dets.where((d) => d.conf >= 0.5).toList(),
        iouThresh: 0.45,
        topK: 50,
      );

      // 7) scale bbox ไปตามขนาดภาพกล้องจริง (จะไป map กับ preview อีกที)
      for (final d in filtered) {
        final xmin = (d.x - d.w / 2) * imgW.value;
        final ymin = (d.y - d.h / 2) * imgH.value;
        final xmax = (d.x + d.w / 2) * imgW.value;
        final ymax = (d.y + d.h / 2) * imgH.value;

        final rx = math.max(0.0, xmin);
        final ry = math.max(0.0, ymin);
        final rw = math.min(imgW.value, xmax) - rx;
        final rh = math.min(imgH.value, ymax) - ry;

        final clsName = (d.cls >= 0 && d.cls < labels.length)
            ? labels[d.cls]
            : 'Unknown';

        recognitions.add({
          'detectedClass': clsName,
          'confidenceInClass': d.conf,
          'rect': {'x': rx, 'y': ry, 'w': rw, 'h': rh},
        });

        if (clsName == 'ripe') {
          ripeCount.value++;
        } else if (clsName == 'unripe') {
          unripeCount.value++;
        }
      }

      // 8) บันทึกภาพเมื่อถูกสั่ง (ไม่ใช่ทุกเฟรม)
      if (_saveNextFrame) {
        _saveNextFrame = false;
        await _saveJpeg(resized);
      }
    } catch (e) {
      debugPrint('❌ Inference failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// ========== HELPERS ==========

  // สร้างอินพุตตามชนิด (float32 หรือ uint8)
  // ** แก้ไขตรงนี้: ให้คืนค่าเป็น List 4 มิติที่ซ้อนกัน **
  Object _makeInput(img_lib.Image image) {
    if (_inputType == TensorType.float32) {
      List<List<List<List<double>>>> inputList = List.generate(
        1, // Batch size
        (_) => List.generate(
          inH!, // Height
          (_) => List.generate(
            inW!, // Width
            (_) => List.generate(3, (_) => 0.0), // 3 channels (R, G, B)
          ),
        ),
      );

      for (int y = 0; y < inH!; y++) {
        for (int x = 0; x < inW!; x++) {
          final px = image.getPixel(x, y);
          inputList[0][y][x][0] = img_lib.getRed(px) / 255.0;
          inputList[0][y][x][1] = img_lib.getGreen(px) / 255.0;
          inputList[0][y][x][2] = img_lib.getBlue(px) / 255.0;
        }
      }
      return inputList;
    } else {
      // quantized uint8
      List<List<List<List<int>>>> inputList = List.generate(
        1, // Batch size
        (_) => List.generate(
          inH!, // Height
          (_) => List.generate(
            inW!, // Width
            (_) => List.generate(3, (_) => 0), // 3 channels (R, G, B)
          ),
        ),
      );

      for (int y = 0; y < inH!; y++) {
        for (int x = 0; x < inW!; x++) {
          final px = image.getPixel(x, y);
          inputList[0][y][x][0] = img_lib.getRed(px);
          inputList[0][y][x][1] = img_lib.getGreen(px);
          inputList[0][y][x][2] = img_lib.getBlue(px);
        }
      }
      return inputList;
    }
  }

  // แปลง YUV420 → RGB (ยังช้า ถ้าอยากเฟรมเรตสูงมาก แนะนำเขียน native/FFI)
  img_lib.Image _yuv420ToImage(CameraImage cameraImage) {
    final w = cameraImage.width;
    final h = cameraImage.height;
    final img = img_lib.Image(w, h);

    final pY = cameraImage.planes[0];
    final pU = cameraImage.planes[1];
    final pV = cameraImage.planes[2];

    final yBytes = pY.bytes;
    final uBytes = pU.bytes;
    final vBytes = pV.bytes;

    final rsY = pY.bytesPerRow;
    final psY = pY.bytesPerPixel ?? 1;
    final rsU = pU.bytesPerRow;
    final psU = pU.bytesPerPixel ?? 1;
    final rsV = pV.bytesPerRow;
    final psV = pV.bytesPerPixel ?? 1;

    int R, G, B;
    int yValue, uValue, vValue;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yIndex = y * rsY + x * psY;
        final uvX = x >> 1;
        final uvY = y >> 1;
        final uIndex = uvY * rsU + uvX * psU;
        final vIndex = uvY * rsV + uvX * psV;

        final Y = yBytes[yIndex] & 0xff;
        final U = (uBytes[uIndex.clamp(0, uBytes.length - 1)] & 0xff) - 128;
        final V = (vBytes[vIndex.clamp(0, vBytes.length - 1)] & 0xff) - 128;

        // BT.601
        R = (Y + 1.370705 * V).round();
        G = (Y - 0.337633 * U - 0.698001 * V).round();
        B = (Y + 1.732446 * U).round();

        R = R.clamp(0, 255);
        G = G.clamp(0, 255);
        B = B.clamp(0, 255);

        img.setPixelRgba(x, y, R, G, B, 255);
      }
    }
    return img;
  }

  Future<void> _saveJpeg(img_lib.Image image) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/palm_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(path)
        ..writeAsBytesSync(img_lib.encodeJpg(image, quality: 92));

      final success = await GallerySaver.saveImage(file.path);
      if (success ?? false) {
        debugPrint('💾 Saved to gallery: $path');
      } else {
        debugPrint('⚠️ Failed to save to gallery');
      }
    } catch (e) {
      debugPrint('⚠️ Save failed: $e');
    }
  }

  // กล่องตรวจจับ
  List<_Det> _parseDetections(Object output) {
    final dets = <_Det>[];

    if (_layoutCHW) {
      // [1, 6, 8400] => (x, y, w, h, conf, cls)
      final out = (output as List)[0] as List; // [6][8400]
      final xs = out[0] as List<double>;
      final ys = out[1] as List<double>;
      final ws = out[2] as List<double>;
      final hs = out[3] as List<double>;
      final confs = out[4] as List<double>;
      final clses = out[5] as List<double>;
      for (int i = 0; i < numDet!; i++) {
        dets.add(_Det(xs[i], ys[i], ws[i], hs[i], confs[i], clses[i].toInt()));
      }
    } else {
      // [1, 8400, 6]
      final out = (output as List)[0] as List; // [8400][6]
      for (int i = 0; i < numDet!; i++) {
        final row = out[i] as List<double>;
        dets.add(_Det(row[0], row[1], row[2], row[3], row[4], row[5].toInt()));
      }
    }
    return dets;
  }

  // NMS ง่าย ๆ
  List<_Det> _nms(List<_Det> dets, {double iouThresh = 0.45, int topK = 100}) {
    dets.sort((a, b) => b.conf.compareTo(a.conf));
    final keep = <_Det>[];
    final used = List<bool>.filled(dets.length, false);

    for (int i = 0; i < dets.length; i++) {
      if (used[i]) continue;
      final a = dets[i];
      keep.add(a);
      if (keep.length >= topK) break;

      for (int j = i + 1; j < dets.length; j++) {
        if (used[j]) continue;
        final b = dets[j];
        if (a.cls != b.cls) continue; // NMS per-class
        if (_iou(a, b) > iouThresh) used[j] = true;
      }
    }
    return keep;
  }

  double _iou(_Det a, _Det b) {
    final ax1 = a.x - a.w / 2,
        ay1 = a.y - a.h / 2,
        ax2 = a.x + a.w / 2,
        ay2 = a.y + a.h / 2;
    final bx1 = b.x - b.w / 2,
        by1 = b.y - b.h / 2,
        bx2 = b.x + b.w / 2,
        by2 = b.y + b.h / 2;

    final interX1 = math.max(ax1, bx1);
    final interY1 = math.max(ay1, by1);
    final interX2 = math.min(ax2, bx2);
    final interY2 = math.min(ay2, by2);

    final interW = math.max(0.0, interX2 - interX1);
    final interH = math.max(0.0, interY2 - interY1);
    final interArea = interW * interH;

    final areaA = (ax2 - ax1) * (ay2 - ay1);
    final areaB = (bx2 - bx1) * (by2 - by1);
    final union = areaA + areaB - interArea + 1e-6;

    return interArea / union;
  }
}

class _Det {
  final double x, y, w, h, conf;
  final int cls;
  _Det(this.x, this.y, this.w, this.h, this.conf, this.cls);
}