import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:palm_app/controller/detection_controller.dart';


class StreanDetectionPage
 extends GetView<DetectionController> {
  const StreanDetectionPage
  ({super.key});

  @override
  Widget build(BuildContext context) {
    return  Scaffold(appBar: AppBar(title: Text('Detection page '),),);
  }
}