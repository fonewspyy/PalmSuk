import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:palm_app/color/colors.dart';
import 'package:palm_app/controller/detection_controller.dart';

class StreanDetectionPage extends GetView<DetectionController> {
  const StreanDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    List<Widget> renderBoxes(Size screen) {
      if (controller.imageHeight.value == 0.0 ||
          controller.imageWidth.value == 0.0)
        return [];
      double factorX = screen.width;
      double factorY =
          controller.imageWidth / controller.imageWidth.value * screen.width;
      // Color blue = PBlue;
      return controller.recognitions!.map((re) {
        if (re["confidenceInClass"] as double >= 0.5) {
          return Positioned(
            left: (re["rect"]["x"] * factorX),
            top: (re["rect"]["y"] * factorY),
            width: (re["rect"]["w"] * factorX),
            height: (re["rect"]["h"] * factorY),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                border: Border.all(color: PBlue, width: 2),
              ),
              child: Text(
                "${re["detectedClass"]} ${(re["confidenceInClass"] * 100).toString()}",
                style: TextStyle(
                  background: Paint()..color = PBlue,
                  color: PWhite,
                  fontSize: 12.0,
                ),
              ),
            ),
          );
        } else {
          return Text("");
        }
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(title: Text('Detection page ')),
      body: Obx(
        () => controller.isInitialized.value
            ? Stack(children: [CameraPreview(controller.cameraController), ...renderBoxes(size)])
            : Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
