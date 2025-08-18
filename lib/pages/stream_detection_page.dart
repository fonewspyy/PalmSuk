import 'dart:math' as math; // <-- เพิ่มถ้ายังไม่มี
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:palm_app/color/colors.dart';
import 'package:palm_app/controller/detection_controller.dart';

class StreanDetectionPage extends GetView<DetectionController> {
  const StreanDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    Color getBorderColor(String detectedClass) {
      switch (detectedClass) {
        case 'ripe':   return PGreen;
        case 'unripe': return PRed;
        default:       return PRed;
      }
    }

    // 🔧 รับขนาด overlay จริง + คำนวณ BoxFit.cover mapping ให้ bbox วาดตรง
    List<Widget> renderBoxes(Size overlaySize) {
      if (controller.imageHeight.value == 0.0 || controller.imageWidth.value == 0.0) {
        return const [];
      }

      // ขนาดวิดีโอจากกล้อง (ก่อนการวาดลงจอ)
      final previewSize = controller.cameraController.value.previewSize;
      if (previewSize == null) return const [];

      final double pw = previewSize.width;
      final double ph = previewSize.height;

      // ขนาดพื้นที่ที่แสดงพรีวิวจริงบนจอ (overlay)
      final double W = overlaySize.width;
      final double H = overlaySize.height;

      // BoxFit.cover: scale = max(W/pw, H/ph), แล้วเกิด offset dx/dy
      final double scale = math.max(W / pw, H / ph);
      final double dw = pw * scale;
      final double dh = ph * scale;
      final double dx = (W - dw) / 2.0;
      final double dy = (H - dh) / 2.0;

      return controller.recognitions.map<Widget>((re) {
        final conf = (re["confidenceInClass"] as num).toDouble();
        if (conf < controller.minConf) return const SizedBox.shrink();

        final rect = re["rect"] as Map; // {x,y,w,h} normalized 0..1
        // แปลง normalized -> พิกเซลในภาพหลัง cover (dw x dh) แล้วชดเชย dx/dy
        final double left = dx + (rect["x"] as num).toDouble() * dw;
        final double top  = dy + (rect["y"] as num).toDouble() * dh;
        final double w    = (rect["w"] as num).toDouble() * dw;
        final double h    = (rect["h"] as num).toDouble() * dh;

        // ตัดขอบกันหลุด
        final double clampedLeft = left.clamp(0.0, W - 1);
        final double clampedTop  = top.clamp(0.0, H - 1);
        final double clampedW    = (clampedLeft + w > W) ? (W - clampedLeft) : w;
        final double clampedH    = (clampedTop + h > H) ? (H - clampedTop) : h;

        return Positioned(
          left: clampedLeft,
          top: clampedTop,
          width: clampedW,
          height: clampedH,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: Border.all(
                color: getBorderColor(re["detectedClass"]),
                width: 2,
              ),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: getBorderColor(re["detectedClass"]),
                child: Text(
                  "${re["detectedClass"]} ${(conf * 100).toStringAsFixed(0)}%",
                  style: TextStyle(color: PWhite, fontSize: 12.0),
                ),
              ),
            ),
          ),
        );
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('PALM SUK',
            style: TextStyle(color: PWhite, fontSize: 25, fontWeight: FontWeight.bold)),
        backgroundColor: PBrown,
      ),
      body: Obx(() {
        return Column(
          children: [
            // 🔳 ครึ่งบน: กล้องขนาด "เดิม" (คง Expanded/padding/ClipRRect แบบที่คุณมี)
            Expanded(
              flex: 5,
              child: Container(
                color: Pbgcolor,
                padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 40),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Obx(() {
                      if (!controller.isInitialized.value) {
                        return Image.asset('assets/models/palmsuk1.jpg', fit: BoxFit.cover);
                      }
                      // ⬇️ ไม่บังคับ AspectRatio — คง "ขนาดเดิมของ UI" ตามพื้นที่ที่มี
                      return LayoutBuilder(
                        builder: (_, constraints) {
                          final overlayW = constraints.maxWidth;
                          final overlayH = constraints.maxHeight; // << ใช้เต็มพื้นที่เดิม

                          return SizedBox(
                            width: overlayW,
                            height: overlayH,
                            child: Stack(
                              children: [
                                // แสดงกล้องแบบ cover เหมือนเดิม
                                Positioned.fill(
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: controller.cameraController.value.previewSize?.width ?? overlayW,
                                      height: controller.cameraController.value.previewSize?.height ?? overlayH,
                                      child: CameraPreview(controller.cameraController),
                                    ),
                                  ),
                                ),
                                // วาด bbox โดย map ด้วยสูตร BoxFit.cover ข้างบน
                                ...renderBoxes(Size(overlayW, overlayH)),
                              ],
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ),
            ),

            // 📊 ครึ่งล่าง: ผลลัพธ์
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(color: Pbgcolor),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    margin: const EdgeInsets.only(top: 0, left: 40, right: 40, bottom: 30),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        const SizedBox(height: 25),
                        Text('ผลการวิเคราะห์',
                            style: TextStyle(color: PBrown, fontWeight: FontWeight.bold, fontSize: 25)),
                        const SizedBox(height: 15),
                        _buildResultRow('ผลปาล์มสุก', PGreen, controller.ripeCount.value),
                        const SizedBox(height: 10),
                        _buildResultRow('ผลปาล์มดิบ', PRed, controller.unripeCount.value),
                        GestureDetector(
                          onTap: () => controller.toggleCamera(),
                          child: Obx(() => Container(
                                margin: const EdgeInsets.symmetric(vertical: 25),
                                width: 260,
                                height: 40,
                                decoration: BoxDecoration(color: PBrown, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      controller.isCameraRunning.value ? Icons.videocam_off : Icons.videocam,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      controller.isCameraRunning.value ? 'STOP DETECT' : 'START DETECT',
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              )),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildResultRow(String label, Color color, int count) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label : $count',
            style: const TextStyle(
              fontSize: 16,
              color: PGray,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}
