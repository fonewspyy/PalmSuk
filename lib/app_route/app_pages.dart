import 'package:get/route_manager.dart';
import 'package:palm_app/app_route/app_route.dart';
import 'package:palm_app/binding/detection_binding.dart';
import 'package:palm_app/pages/detection_page.dart';
import 'package:palm_app/pages/home_page.dart';
import 'package:palm_app/pages/palm_report_page.dart';
import 'package:palm_app/pages/stream_detection_page.dart';

class AppPages {
  static final pages = [
    // GetPage(name: AppRoutes.homePage, page: () => const HomePage()),
    // GetPage(
    //   binding: DetectionBinding(),
    //   name: AppRoutes.detectionPage,
    //   page: () => DetectionPicture(),
    // ),
    GetPage(
      name: AppRoutes.streamPage,
      binding: DetectionBinding(),
      page: () => const StreanDetectionPage(),
    ),
    // เส้นทางสำหรับหน้า PalmReportPage
    GetPage(
      name: AppRoutes.palmReportPage,  // ตั้งชื่อเส้นทางใน AppRoutes
      page: () => const PalmReportPage(),  // เชื่อมโยงไปยัง PalmReportPage
    ),
  ];
}
