// lib/services/yolo_v8_nms.dart
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloV8Nms {
  late Interpreter _interpreter;
  List<String> _labels = [];
  late int _inputW, _inputH;
  bool _ready = false;

  Future<void> load({
    String modelAsset = 'assets/models/palm.tflite',
    String labelsAsset = 'assets/models/palm.txt',
    int threads = 4,
  }) async {
    final options = InterpreterOptions()..threads = threads;
    _interpreter = await Interpreter.fromAsset(modelAsset, options: options);

    final inputShape = _interpreter.getInputTensor(0).shape; // [1,H,W,3]
    _inputH = inputShape[1];
    _inputW = inputShape[2];

    final labelsStr = await rootBundle.loadString(labelsAsset);
    _labels = labelsStr
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _ready = true;
  }

  bool get isReady => _ready;

  String _labelOf(num idx) {
    final i = idx.toInt();
    if (_labels.isEmpty) return '$i';
    if (i >= 0 && i < _labels.length) return _labels[i];
    return '$i';
  }

  /// YUV420 -> RGB -> resize -> Float32 [1,H,W,3] normalize 0..1
  Float32List _preprocess(CameraImage image) {
    final rgb = _yuv420ToRgb(image);
    final resized = img.copyResize(rgb, width: _inputW, height: _inputH);

    final data = Float32List(_inputW * _inputH * 3);
    int p = 0;
    for (int y = 0; y < _inputH; y++) {
      for (int x = 0; x < _inputW; x++) {
        final px = resized.getPixel(x, y);
        data[p++] = img.getRed(px) / 255.0;
        data[p++] = img.getGreen(px) / 255.0;
        data[p++] = img.getBlue(px) / 255.0;
      }
    }
    return data;
  }

  /// ใช้กับโมเดล YOLO ที่ export ด้วย NMS แล้ว → output[0] = [1,N,6]: [x1,y1,x2,y2,score,cls]
  List<Map<String, dynamic>> _decodeNms(
    List output, {
    double scoreTh = 0.5,
  }) {
    final List detections = output[0]; // [N,6]
    final out = <Map<String, dynamic>>[];

    for (final det in detections) {
      if (det is! List || det.length < 6) continue;

      double x1 = (det[0] as num).toDouble();
      double y1 = (det[1] as num).toDouble();
      double x2 = (det[2] as num).toDouble();
      double y2 = (det[3] as num).toDouble();
      final score = (det[4] as num).toDouble();
      final cls = det[5] as num;

      if (score < scoreTh) continue;

      // สมมติค่ากล่องเป็นพิกเซลบนสเกลอินพุต → normalize เป็น 0..1
      x1 = (x1 / _inputW).clamp(0.0, 1.0);
      y1 = (y1 / _inputH).clamp(0.0, 1.0);
      x2 = (x2 / _inputW).clamp(0.0, 1.0);
      y2 = (y2 / _inputH).clamp(0.0, 1.0);

      final w = (x2 - x1).clamp(0.0, 1.0);
      final h = (y2 - y1).clamp(0.0, 1.0);
      if (w <= 0 || h <= 0) continue;

      out.add({
        "rect": {"x": x1, "y": y1, "w": w, "h": h},
        "detectedClass": _labelOf(cls),
        "confidenceInClass": score,
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> runOnFrame(CameraImage image) async {
    if (!_ready) throw StateError('Interpreter not ready. Call load() first.');

    final floats = _preprocess(image);
    final input = floats.reshape([1, _inputH, _inputW, 3]); // → List

    final outTensor = _interpreter.getOutputTensor(0);
    final outShape = outTensor.shape; // expect [1, N, 6]
    if (outShape.length != 3 || outShape[2] != 6) {
      throw StateError('Unexpected output shape: $outShape (need [1,N,6])');
    }

    final N = outShape[1];
    final output = List.generate(1, (_) => List.generate(N, (_) => List.filled(6, 0.0)));

    _interpreter.run(input, output);
    return _decodeNms(output, scoreTh: 0.5);
  }

  img.Image _yuv420ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel!;

    // image 3.x → ใช้ positional args
    final rgb = img.Image(width, height);

    for (int y = 0; y < height; y++) {
      final uvRow = uvRowStride * (y >> 1);
      for (int x = 0; x < width; x++) {
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;

        final int yp = yPlane.bytes[y * yPlane.bytesPerRow + x];
        final int up = uPlane.bytes[uvIndex];
        final int vp = vPlane.bytes[uvIndex];

        final double Y = yp.toDouble();
        final double U = up.toDouble() - 128.0;
        final double V = vp.toDouble() - 128.0;

        double r = Y + 1.402 * V;
        double g = Y - 0.344136 * U - 0.714136 * V;
        double b = Y + 1.772 * U;

        final ri = r.clamp(0.0, 255.0).toInt();
        final gi = g.clamp(0.0, 255.0).toInt();
        final bi = b.clamp(0.0, 255.0).toInt();

        rgb.setPixel(x, y, img.getColor(ri, gi, bi));
      }
    }
    return rgb;
  }

  Future<void> close() async {
    _interpreter.close();
    _ready = false;
  }
}

/// reshape สำหรับ Float32List → List (ซ้อนหลายมิติ)
extension _ReshapeFloat32 on Float32List {
  List reshape(List<int> dims) {
    int total = 1;
    for (final d in dims) total *= d;
    assert(total == length, 'reshape size mismatch');

    int offset = 0;
    dynamic build(int dim) {
      if (dim == dims.length - 1) {
        final len = dims[dim];
        final out = List<double>.filled(len, 0.0, growable: false);
        for (int i = 0; i < len; i++) {
          out[i] = this[offset++];
        }
        return out;
      } else {
        final len = dims[dim];
        return List.generate(len, (_) => build(dim + 1), growable: false);
      }
    }

    return build(0) as List;
  }
}
