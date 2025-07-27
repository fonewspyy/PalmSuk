import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:palm_app/color/colors.dart';
import 'package:palm_app/controller/detection_controller.dart';

class DetectionPicture extends GetView<DetectionController> {
  const DetectionPicture({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detect Picure', style: TextStyle(color: PWhite)),
        backgroundColor: PGreen,
      ),
      body: Obx(() {
        if (controller.isInitialized.value == false) {
          return Center(child: CircularProgressIndicator());
        } else {
          return Stack(
            children: [
              CameraPreview(controller.cameraController),
              Positioned(
                right: 10,
                bottom: 30,
                child: Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PBlack.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Obx(
                    () => Text(
                      controller.result.value,
                      style: TextStyle(color: PWhite, fontSize: 20),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      }),
      floatingActionButton: FloatingActionButton(onPressed: (){controller.takePicture();},
      child: Icon(Icons.camera_alt),),
    );
  }
}
