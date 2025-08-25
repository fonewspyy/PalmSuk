import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:palm_app/color/colors.dart';
import 'package:palm_app/controller/detection_controller.dart';

class StreanDetectionPage extends GetView<DetectionController> {
  const StreanDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    // เปลี่ยนสีrenderBox
    Color getBorderColor(String detectedClass) {
      switch (detectedClass) {
        case 'ripe':
          return PGreen;
        default:
          return PRed;
      }
    }

    List<Widget> renderBoxes(Size screen) {
      // แก้ไขจาก imageHeight/imageWidth เป็น imgH/imgW
      if (controller.imgH.value == 0.0 ||
          controller.imgW.value == 0.0) {
        return [];
      }

      // แก้ไขจาก imageHeight/imageWidth เป็น imgH/imgW
      double factorX = screen.width / controller.imgW.value;
      double factorY = screen.height / controller.imgH.value;

      return controller.recognitions.map((re) {
        if (re["confidenceInClass"] as double >= 0.5) {
          return Positioned(
            left: re["rect"]["x"] * factorX,
            top: re["rect"]["y"] * factorY,
            width: re["rect"]["w"] * factorX,
            height: re["rect"]["h"] * factorY,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                border: Border.all(
                  color: getBorderColor(re["detectedClass"]),
                  width: 2,
                ),
              ),
              child: Text(
                "${re["detectedClass"]} ${(re["confidenceInClass"] * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  background: Paint()
                    ..color = getBorderColor(re["detectedClass"]),
                  color: PWhite,
                  fontSize: 12.0,
                ),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      }).toList();
    }

    // ต้องดึงขนาดของหน้าจอมาใช้ก่อนใน build method
    final Size size = MediaQuery.of(context).size;


    return Scaffold(
      appBar: AppBar(
        title: Text(
          'PALM SUK',
          style: TextStyle(
            color: PWhite,
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: PBrown,
      ),
      body: Obx(
        () => Column(
          children: [
            // ครึ่งบน: กล้อง
            Expanded(
              flex: 5,
              child: Container(
                // margin: EdgeInsets.symmetric(vertical: 0, horizontal: 40),
                color: Pbgcolor,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 40,
                  ),
                  child: SizedBox(
                    child: Center(
                      child: Container(
                        color: Pbgcolor,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            children: [
                              Obx(() {
                                if (controller.isInitialized.value) {
                                  return Stack(
                                    children: [
                                      CameraPreview(
                                        controller.cameraController,
                                      ),
                                      ...renderBoxes(size), // ส่ง size เข้าไป
                                    ],
                                  );
                                } else {
                                  return Image.asset(
                                    'assets/models/palmsuk1.jpg', // เปลี่ยนเป็น path ของ icon รูปกล้องที่คุณเตรียมไว้
                                  );
                                }
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ครึ่งล่าง: ผลลัพธ์
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(color: Pbgcolor),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    margin: const EdgeInsets.only(
                      top: 0,
                      left: 40,
                      right: 40,
                      bottom: 30,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 25, bottom: 15),
                            child: Text(
                              'ผลการวิเคราะห์',
                              style: TextStyle(
                                color: PBrown,
                                fontWeight: FontWeight.bold,
                                fontSize: 25,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        _buildResultRow(
                          'ผลปาล์มสุก',
                          PGreen,
                          controller.ripeCount.value, // ใช้ ripeCount
                        ),
                        const SizedBox(height: 10),
                        _buildResultRow(
                          'ผลปาล์มดิบ',
                          PRed,
                          controller.unripeCount.value, // ใช้ unripeCount
                        ),
                        GestureDetector(
                          onTap: () => controller.toggleCamera(),
                          child: Obx(
                            () => Container(
                              margin: EdgeInsets.symmetric(vertical: 25),
                              // padding: EdgeInsets.symmetric(vertical: 10),
                              width: 260,
                              height: 40,
                              decoration: BoxDecoration(
                                color: PBrown,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    controller.isCameraRunning.value
                                        ? Icons.videocam_off
                                        : Icons.videocam,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    controller.isCameraRunning.value
                                        ? 'STOP DETECT'
                                        : 'START DETECT',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // : Center(child: CircularProgressIndicator()),
      ),
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