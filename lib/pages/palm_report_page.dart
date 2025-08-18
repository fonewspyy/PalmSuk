// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:palm_app/color/colors.dart';
// import 'package:palm_app/controller/detection_controller.dart';

// class PalmReportPage extends StatelessWidget {
//   const PalmReportPage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     // เพิ่มการเข้าถึง controller
//     final controller = Get.find<DetectionController>();

//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           'รายงานผลปาล์ม',
//           style: TextStyle(color: PWhite, fontWeight: FontWeight.bold),
//         ),
//         leading: IconButton(
//           icon: Icon(
//             Icons.arrow_back, // ไอคอนย้อนกลับ
//             color: Colors.white, // เปลี่ยนสีของไอคอนย้อนกลับที่นี่
//           ),
//           onPressed: () {
//             Get.back(); // กลับไปหน้าก่อนหน้า
//           },
//         ),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.refresh, color: PWhite, size: 30),
//             onPressed: () {
//               // ฟังก์ชันที่ใช้รีเฟรชหรือโหลดข้อมูลใหม่
//             },
//           ),
//         ],
//         backgroundColor: PBrown,
//       ),
//       body: Container(
//         color: Pbgcolor,
//         child: Column(
          
//           children: [
//             // ครึ่งบน: Dashboard แสดงผลรวม
//             Expanded(
//               child: Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Card(
//                   elevation: 5,
//                   color: PWhite,
//                   shape: RoundedRectangleBorder(
//                     side: BorderSide(
//                       color: PBrown, // สีขอบที่ต้องการ
//                       width: 3.0, // ความหนาของขอบ
//                     ),
//                     borderRadius: BorderRadius.circular(12.0), // มุมโค้ง
//                   ),
              
//                   child: Padding(
//                     padding: const EdgeInsets.all(20.0),
//                     child: Column(
//                       children: [
//                         Text(
//                           'Dashboard',
//                           style: TextStyle(
//                             color: PBrown,
//                             fontWeight: FontWeight.bold,
//                             fontSize: 24,
//                           ),
//                         ),
//                         SizedBox(height: 20),
//                         Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Column(
//                               children: [
//                                 Text(
//                                   'ทั้งหมด',
//                                   style: TextStyle(
//                                     color: PBrown,
//                                     fontSize: 18,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                                 Text(
//                                   '${controller.totalLaptopCount.value + controller.totalKeyboardCount.value} ทลาย',
//                                   style: TextStyle(color: PBrown, fontSize: 22),
//                                 ),
//                               ],
//                             ),
//                             Column(
//                               children: [
//                                 Text(
//                                   'ปาล์มสุก',
//                                   style: TextStyle(
//                                     color: PBrown,
//                                     fontSize: 18,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                                 Text(
//                                   '${controller.totalLaptopCount.value} ทลาย',
//                                   style: TextStyle(color: PBrown, fontSize: 22),
//                                 ),
//                               ],
//                             ),
//                             Column(
//                               children: [
//                                 Text(
//                                   'ปาล์มดิบ',
//                                   style: TextStyle(
//                                     color: PBrown,
//                                     fontSize: 18,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                                 Text(
//                                   '${controller.totalKeyboardCount.value} ทลาย',
//                                   style: TextStyle(color: PBrown, fontSize: 22),
//                                 ),
//                               ],
//                             ),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             ),
        
//             // ครึ่งล่าง: ตารางแสดงผลการตรวจจับ
//             Expanded(
//               child: Obx(() {
//                 return Column(
//                   children: [
//                     Padding(
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 20,
//                         vertical: 10,
//                       ),
//                       child: Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Text(
//                             'ข้อมูลการตรวจจับ',
//                             style: TextStyle(
//                               fontSize: 20,
//                               fontWeight: FontWeight.bold,
//                               color: PBrown,
//                             ),
//                           ),
//                           ElevatedButton(
//                             onPressed: () {
//                               _selectDate(
//                                 context,
//                                 controller,
//                               ); // เรียกฟังก์ชันเลือกวันที่
//                             },
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: PBrown,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(8),
//                               ),
//                             ),
//                             child: Text(
//                               'เลือกวันที่',
//                               style: TextStyle(color: PWhite),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Expanded(
//                       child: ListView.builder(
//                         itemCount: controller.palmRecords.length,
//                         itemBuilder: (context, index) {
//                           var record = controller.palmRecords[index];
//                           return Card(
//                             margin: EdgeInsets.symmetric(
//                               vertical: 10,
//                               horizontal: 15,
//                             ),
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             elevation: 4,
//                             child: ListTile(
//                               title: Text(
//                                 'วันที่: ${record['date']}',
//                                 style: TextStyle(
//                                   fontWeight: FontWeight.bold,
//                                   color: PBrown,
//                                 ),
//                               ),
//                               subtitle: Text(
//                                 'Laptop: ${record['laptop']} ทลาย, Keyboard: ${record['keyboard']} ทลาย',
//                                 style: TextStyle(
//                                   fontSize: 14,
//                                   color: PGray, // สีฟอนต์ที่อ่านง่าย
//                                 ),
//                               ),
//                               trailing: Text(
//                                 record['timestamp'],
//                                 style: TextStyle(
//                                   fontSize: 12,
//                                   color: PGray, // สีฟอนต์ที่อ่านง่าย
//                                 ),
//                               ),
//                             ),
//                           );
//                         },
//                       ),
//                     ),
//                   ],
//                 );
//               }),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ฟังก์ชันสำหรับแสดง Date Picker เพื่อเลือกวันที่
//   Future<void> _selectDate(
//     BuildContext context,
//     DetectionController controller,
//   ) async {
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: DateTime.now(),
//       firstDate: DateTime(2025),
//       lastDate: DateTime(2026),
//     );
//     if (picked != null && picked != DateTime.now()) {
//       // เรียกฟังก์ชันใน controller เพื่อกรองข้อมูลตามวันที่ที่เลือก
//       String selectedDate =
//           '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
//       controller.filterByDate(selectedDate); // กรองข้อมูลตามวันที่
//     }
//   }
// }
