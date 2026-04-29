import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'package:firebase_core/firebase_core.dart'; // Bắt buộc phải có
import 'services/notification_service.dart';
void main() async {
  // Đảm bảo Flutter Binding được khởi tạo trước khi gọi async
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Khởi tạo Service Thông báo
  await NotificationService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Todo App',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const MainScreen(),
    );
  }
}