import 'package:flutter/material.dart';
import 'today_screen.dart';
import 'upcoming_screen.dart';
import 'inbox_screen.dart';
import 'chat_screen.dart';
import 'add_task_screen.dart';
import 'browse_screen.dart';
import 'groups_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1;
  int refreshCounter = 0;
  final GlobalKey<InboxScreenState> inboxKey = GlobalKey();
  final GlobalKey<TodayScreenState> todayKey = GlobalKey();
  final GlobalKey<UpcomingScreenState> upcomingKey = GlobalKey();

  late final List<Widget> _screens = [
    InboxScreen(key: inboxKey),
    TodayScreen(key: todayKey),
    UpcomingScreen(key: upcomingKey),

    const GroupsScreen(),
    const BrowseScreen(),
  ];

  void openChat() {
    // KIỂM TRA ĐĂNG NHẬP
    if (FirebaseAuth.instance.currentUser == null) {
      // Nếu chưa đăng nhập -> Cảnh báo và chuyển sang tab Hồ sơ (Browse)
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Yêu cầu Đăng nhập"),
          content: const Text("Tính năng Trợ lý AI chỉ dành cho thành viên đã đăng nhập. Bạn có muốn Đăng nhập ngay không?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Để sau")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 3); // 3 là index của tab Browse
              },
              child: const Text("Đăng nhập"),
            )
          ],
        ),
      );
      return; // Chặn không cho mở ChatScreen
    }

    // Nếu đã đăng nhập -> Cho mở bình thường
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChatScreen()),
    ).then((value) {
      // 🔥 ĐOẠN CODE NÀY SẼ CHẠY NGAY LẬP TỨC KHI BẠN ĐÓNG CHAT SCREEN
      setState(() {
        refreshCounter++; // Thay đổi biến này để ép màn hình làm mới
      });
    });
  }

  void openAddTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddTaskScreen(),
      ),
    );

    // reload lại data sau khi thêm
    if (result == true) {
      inboxKey.currentState?.loadTasks();
      todayKey.currentState?.loadTasks();
      upcomingKey.currentState?.loadTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],

      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80), // 🔥 đẩy lên
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: "btnChatAI",
              backgroundColor: Colors.blue,
              onPressed: openChat,
              child: const Icon(Icons.smart_toy),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: "btnAddTask",
              backgroundColor: Colors.red,
              onPressed: openAddTask,
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.red,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.inbox), label: "Inbox"),
          BottomNavigationBarItem(icon: Icon(Icons.today), label: "Today"),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: "Upcoming"),
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: "Nhóm"), // 👉 THÊM NÚT NÀY VÀO
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Hồ sơ"),
        ],
      ),
    );
  }
}