import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:get/get.dart';
import 'dart:math' as math;

class DetectionController extends GetxController {
  // =============== Camera ===============
  RxBool isStreaming = false.obs;
  late CameraController cameraController;
  RxBool isInitialized = false.obs;
  RxBool isCameraRunning = false.obs;

  // =============== Inference ===============
  bool _busy = false;
  Interpreter? interpreter;

  TensorType? _inputType;
  TensorType? _outputType;

  // Model input size
  int? inW, inH;

  // Output layout
  int? valuesPerDet, numDet;
  bool _layoutCHW = false; // true => [1,6,N]; false => [1,N,6]

  // Quant params (fallbacks)
  double _inScale = 1.0 / 255.0;
  int _inZero = 0;
  double _outScale = 1.0;
  int _outZero = 0;

  // Preallocated input buffers
  List<List<List<List<double>>>>? _inputF; // float32/float16
  List<List<List<List<int>>>>? _inputI;    // int8/uint8

  // Cached resize maps
  List<int>? _mapX, _mapY, _mapXuv, _mapYuv;
  int _srcW = -1, _srcH = -1;

  // Frame skipper (1 = ทุกเฟรม)
  int processEveryN = 1;
  int _frameIdx = 0;

  // Labels
  List<String> labels = [];

  // Results/state
  RxList<Map<String, dynamic>> recognitions = <Map<String, dynamic>>[].obs;
  RxInt ripeCount = 0.obs;
  RxInt unripeCount = 0.obs;
  RxDouble imgW = 0.0.obs;
  RxDouble imgH = 0.0.obs;

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
    try {
      interpreter?.close();
    } catch (_) {}
    super.onClose();
  }

  // =============== Model loading ===============
  Future<void> _loadModelAndLabels() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      try {
        options.addDelegate(XNNPackDelegate()); // best on CPU
      } catch (_) {}

      interpreter = await Interpreter.fromAsset(
        'assets/models/best_int8.tflite',
        options: options,
      );
      debugPrint('✅ TFLite model loaded');

      final labelStr = await rootBundle.loadString('assets/models/palm.txt');
      labels = labelStr
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      debugPrint('✅ Labels: $labels');

      // Input tensor
      final inTensor = interpreter!.getInputTensors().first;
      _inputType = inTensor.type;
      final inShape = inTensor.shape; // [1,H,W,3]
      if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
        throw Exception('Unexpected input shape: $inShape (expect [1,h,w,3])');
      }
      inH = inShape[1];
      inW = inShape[2];

      final inQ = inTensor.params;
      if (inQ.scale != 0.0) _inScale = inQ.scale;
      _inZero = inQ.zeroPoint;

      // Output tensor
      final outTensor = interpreter!.getOutputTensors().first;
      _outputType = outTensor.type;
      final outShape = outTensor.shape; // [1,6,N] or [1,N,6]
      if (outShape.length != 3 || outShape[0] != 1) {
        throw Exception('Unexpected output shape: $outShape');
      }
      if (outShape[1] == 6) {
        _layoutCHW = true; valuesPerDet = outShape[1]; numDet = outShape[2];
      } else if (outShape[2] == 6) {
        _layoutCHW = false; valuesPerDet = outShape[2]; numDet = outShape[1];
      } else {
        throw Exception('Cannot find 6-dim per detection in output: $outShape');
      }

      final outQ = outTensor.params;
      if (outQ.scale != 0.0) _outScale = outQ.scale;
      _outZero = outQ.zeroPoint;

      debugPrint('📥 Input: ${inW}x${inH}, type=$_inputType (scale=$_inScale, zp=$_inZero)');
      debugPrint('📤 Output: layoutCHW=$_layoutCHW, N=$numDet, type=$_outputType (scale=$_outScale, zp=$_outZero)');

      _preparePreallocatedInputs();
    } catch (e, st) {
      debugPrint('❌ Load model/labels failed: $e\n$st');
      interpreter = null;
    }
  }

  void _preparePreallocatedInputs() {
    if (inW == null || inH == null) return;
    final isFloat = _inputType == TensorType.float32 || _inputType == TensorType.float16;
    if (isFloat) {
      _inputF = List.generate(
        1,
        (_) => List.generate(inH!, (_) => List.generate(inW!, (_) => List<double>.filled(3, 0.0))),
      );
      _inputI = null;
    } else {
      _inputI = List.generate(
        1,
        (_) => List.generate(inH!, (_) => List.generate(inW!, (_) => List<int>.filled(3, 0))),
      );
      _inputF = null;
    }
  }

  // =============== Camera ===============
  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(
      cameras.first,
      ResolutionPreset.low, // ปรับเป็น medium ได้ถ้าต้องการ
      imageFormatGroup: ImageFormatGroup.yuv420,
      enableAudio: false,
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

  // =============== Stream Callback ===============
  Future<void> _onStreamFrame(CameraImage img) async {
    if (_busy || interpreter == null || inW == null || inH == null || numDet == null) {
      return;
    }

    // frame skipper
    _frameIdx = (_frameIdx + 1) % processEveryN;
    if (_frameIdx != 0) return;

    _busy = true;
    recognitions.clear();
    ripeCount.value = 0;
    unripeCount.value = 0;

    try {
      imgW.value = img.width.toDouble();
      imgH.value = img.height.toDouble();

      // 1) สร้าง mapping ครั้งเดียวต่อความละเอียด
      _ensureResizeMaps(img.width, img.height, inW!, inH!);

      // 2) YUV420 → RGB + resize + เขียนลง input buffer โดยตรง
      _fillPreallocatedInputFromYUV(img);

      // 3) prepare output
      final output = _prepareOutput();

      // 4) run
      final input = (_inputF != null) ? _inputF! : _inputI!;
      interpreter!.run(input, output);

      // 5) parse + filter + NMS
      final dets = _parseDetections(output);
      final filtered = _nms(
        dets.where((d) => d.conf >= 0.5).toList(),
        iouThresh: 0.45,
        topK: 50,
      );

      // 6) map bbox to camera size
      for (final d in filtered) {
        final xmin = (d.x - d.w / 2) * imgW.value;
        final ymin = (d.y - d.h / 2) * imgH.value;
        final xmax = (d.x + d.w / 2) * imgW.value;
        final ymax = (d.y + d.h / 2) * imgH.value;

        final rx = math.max(0.0, xmin);
        final ry = math.max(0.0, ymin);
        final rw = math.min(imgW.value, xmax) - rx;
        final rh = math.min(imgH.value, ymax) - ry;

        final clsName = (d.cls >= 0 && d.cls < labels.length) ? labels[d.cls] : 'Unknown';

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
    } catch (e, st) {
      debugPrint('❌ Inference failed: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  // =============== Helpers ===============
  void _ensureResizeMaps(int srcW, int srcH, int dstW, int dstH) {
    if (_srcW == srcW && _srcH == srcH && _mapX != null) return;
    _srcW = srcW; _srcH = srcH;
    _mapX  = List<int>.generate(dstW, (x) => ((x * srcW) / dstW).floor().clamp(0, srcW - 1));
    _mapY  = List<int>.generate(dstH, (y) => ((y * srcH) / dstH).floor().clamp(0, srcH - 1));
    _mapXuv = List<int>.generate(dstW, (x) => (((_mapX![x]) >> 1)).clamp(0, (srcW >> 1) - 1));
    _mapYuv = List<int>.generate(dstH, (y) => (((_mapY![y]) >> 1)).clamp(0, (srcH >> 1) - 1));
  }

  // เขียนค่าเข้า input buffer โดยตรง (ไม่มีการสร้างรูปไว้เซฟ)
  void _fillPreallocatedInputFromYUV(CameraImage cameraImage) {
    final isFloat = _inputType == TensorType.float32 || _inputType == TensorType.float16;
    final h = inH!, w = inW!;

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

    for (int dy = 0; dy < h; dy++) {
      final sy = _mapY![dy];
      final suvY = _mapYuv![dy];
      for (int dx = 0; dx < w; dx++) {
        final sx = _mapX![dx];
        final suvX = _mapXuv![dx];

        final yIndex = sy * rsY + sx * psY;
        final uIndex = suvY * rsU + suvX * psU;
        final vIndex = suvY * rsV + suvX * psV;

        final Y = yBytes[yIndex] & 0xff;
        final U = (uBytes[uIndex] & 0xff) - 128;
        final V = (vBytes[vIndex] & 0xff) - 128;

        int R = (Y + 1.370705 * V).round();
        int G = (Y - 0.337633 * U - 0.698001 * V).round();
        int B = (Y + 1.732446 * U).round();
        if (R < 0) R = 0; else if (R > 255) R = 255;
        if (G < 0) G = 0; else if (G > 255) G = 255;
        if (B < 0) B = 0; else if (B > 255) B = 255;

        if (isFloat) {
          _inputF![0][dy][dx][0] = R / 255.0;
          _inputF![0][dy][dx][1] = G / 255.0;
          _inputF![0][dy][dx][2] = B / 255.0;
        } else {
          final qR = (((R / 255.0) / _inScale) + _inZero).round();
          final qG = (((G / 255.0) / _inScale) + _inZero).round();
          final qB = (((B / 255.0) / _inScale) + _inZero).round();
          if (_inputType == TensorType.int8) {
            _inputI![0][dy][dx][0] = qR.clamp(-128, 127);
            _inputI![0][dy][dx][1] = qG.clamp(-128, 127);
            _inputI![0][dy][dx][2] = qB.clamp(-128, 127);
          } else {
            _inputI![0][dy][dx][0] = qR.clamp(0, 255);
            _inputI![0][dy][dx][1] = qG.clamp(0, 255);
            _inputI![0][dy][dx][2] = qB.clamp(0, 255);
          }
        }
      }
    }
  }

  Object _prepareOutput() {
    final isFloat = _outputType == TensorType.float32 || _outputType == TensorType.float16;
    if (_layoutCHW) {
      return [ List.generate(6, (_) => isFloat
          ? List<double>.filled(numDet!, 0.0)
          : List<int>.filled(numDet!, 0)) ];
    } else {
      return [ List.generate(numDet!, (_) => isFloat
          ? List<double>.filled(6, 0.0)
          : List<int>.filled(6, 0)) ];
    }
  }

  double _dq(num q) {
    final isQuantOut = _outputType == TensorType.int8 || _outputType == TensorType.uint8;
    if (isQuantOut) return _outScale * (q - _outZero);
    return q.toDouble();
  }

  // Parse detections — supports raw (cx,cy,w,h) and NMS (x1,y1,x2,y2)
  List<_Det> _parseDetections(Object output) {
    final isFloat = _outputType == TensorType.float32 || _outputType == TensorType.float16;
    final dets = <_Det>[];

    if (_layoutCHW) {
      final out = (output as List)[0] as List;
      final xs = out[0] as List; final ys = out[1] as List;
      final ws = out[2] as List; final hs = out[3] as List;
      final cs = out[4] as List; final ks = out[5] as List;
      for (int i = 0; i < numDet!; i++) {
        final x = isFloat ? (xs[i] as num).toDouble() : _dq(xs[i] as num);
        final y = isFloat ? (ys[i] as num).toDouble() : _dq(ys[i] as num);
        final w = isFloat ? (ws[i] as num).toDouble() : _dq(ws[i] as num);
        final h = isFloat ? (hs[i] as num).toDouble() : _dq(hs[i] as num);
        final conf = isFloat ? (cs[i] as num).toDouble() : _dq(cs[i] as num);
        final cls = (isFloat ? (ks[i] as num).toDouble() : _dq(ks[i] as num)).round();
        dets.add(_Det(x, y, w, h, conf, cls));
      }
      return dets;
    }

    final out = (output as List)[0] as List;
    for (int i = 0; i < numDet!; i++) {
      final row = out[i] as List;
      final v0 = isFloat ? (row[0] as num).toDouble() : _dq(row[0] as num);
      final v1 = isFloat ? (row[1] as num).toDouble() : _dq(row[1] as num);
      final v2 = isFloat ? (row[2] as num).toDouble() : _dq(row[2] as num);
      final v3 = isFloat ? (row[3] as num).toDouble() : _dq(row[3] as num);
      final conf = isFloat ? (row[4] as num).toDouble() : _dq(row[4] as num);
      final cls = (isFloat ? (row[5] as num).toDouble() : _dq(row[5] as num)).round();

      final looksLikeNms = (v2 >= v0 && v3 >= v1) || (v2 > 1.5 || v3 > 1.5);
      if (looksLikeNms) {
        final isPixel = (v2 > 1.5 || v3 > 1.5);
        final sx = isPixel ? (1.0 / inW!) : 1.0;
        final sy = isPixel ? (1.0 / inH!) : 1.0;
        final x1 = v0 * sx, y1 = v1 * sy, x2 = v2 * sx, y2 = v3 * sy;
        final cx = (x1 + x2) / 2.0;
        final cy = (y1 + y2) / 2.0;
        final ww = (x2 - x1).abs();
        final hh = (y2 - y1).abs();
        dets.add(_Det(cx, cy, ww, hh, conf, cls));
      } else {
        dets.add(_Det(v0, v1, v2, v3, conf, cls));
      }
    }
    return dets;
  }

  // Simple per-class NMS
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
        if (a.cls != b.cls) continue;
        if (_iou(a, b) > iouThresh) used[j] = true;
      }
    }
    return keep;
  }

  double _iou(_Det a, _Det b) {
    final ax1 = a.x - a.w / 2, ay1 = a.y - a.h / 2, ax2 = a.x + a.w / 2, ay2 = a.y + a.h / 2;
    final bx1 = b.x - b.w / 2, by1 = b.y - b.h / 2, bx2 = b.x + b.w / 2, by2 = b.y + b.h / 2;

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
