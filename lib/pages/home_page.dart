import 'package:flutter/material.dart';
// import 'package:fluttertensorflow/route/app_routes.dart';
import 'package:get/route_manager.dart';
import 'package:palm_app/app_route/app_route.dart';
import 'package:palm_app/color/colors.dart';

// import '../../core/widgets/buttons/buttons.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Object Detection", style: TextStyle(color: PWhite)),
        backgroundColor: PGreen,
      ),
      body: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Get.toNamed(AppRoutes.streamPage, arguments: {"type":"streaming"});
              },
              child: Text('Start Detection'),
            ),
            ElevatedButton(
              onPressed: () {
                Get.toNamed(AppRoutes.detectionPage, arguments: {"type":"picture"});
              },
              child: Text('Take Picture'),
            ),
          ],
        ),
      ),
    );
  }
}
