import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class TaskDetailListScreen extends StatefulWidget {
  final String listType; // 'ALL', 'COMPLETED', 'PENDING'
  final String title;

  const TaskDetailListScreen({
    super.key,
    required this.listType,
    required this.title,
  });

  @override
  State<TaskDetailListScreen> createState() => _TaskDetailListScreenState();
}

class _TaskDetailListScreenState extends State<TaskDetailListScreen> {
  final DBHelper dbHelper = DBHelper();
  List<Map<String, dynamic>> tasks = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  void loadTasks() async {
    // 🔥 Gọi getAllTasks để lấy CẢ NHỮNG TASK ĐÃ XÓA ẢO
    final data = await dbHelper.getAllTasks();

    List<Map<String, dynamic>> filtered = [];

    if (widget.listType == 'ALL') {
      filtered = data;
    } else if (widget.listType == 'COMPLETED') {
      filtered = data.where((t) => t['isCompleted'] == 1).toList();
    } else if (widget.listType == 'PENDING') {
      filtered = data.where((t) => t['isCompleted'] == 0).toList();
    }

    if (mounted) {
      setState(() {
        tasks = filtered;
        isLoading = false;
      });
    }
  }

  void deletePermanently(Map<String, dynamic> task) async {
    int id = task["id"];
    // Hủy chuông nếu có
    await NotificationService().cancelTask(id);
    // XÓA VĨNH VIỄN KHỎI DATABASE
    await dbHelper.deleteTask(id);

    loadTasks();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Đã xóa vĩnh viễn khỏi thiết bị")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : tasks.isEmpty
          ? const Center(child: Text("Không có công việc nào", style: TextStyle(fontSize: 16, color: Colors.grey)))
          : ListView.builder(
        itemCount: tasks.length,
        itemBuilder: (context, i) {
          final t = tasks[i];
          DateTime time = DateTime.parse(t["datetime"]);
          bool isCompleted = t["isCompleted"] == 1;
          bool isArchived = t["isArchived"] == 1;

          return Dismissible(
            key: Key(t["id"].toString()),
            direction: DismissDirection.endToStart, // Chỉ cho vuốt từ phải sang trái để xóa
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_forever, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              bool? confirm = await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Xóa vĩnh viễn"),
                  content: const Text("Hành động này không thể hoàn tác. Bạn có chắc chắn?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Xóa", style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              return confirm;
            },
            onDismissed: (_) {
              deletePermanently(t);
            },
            child: ListTile(
              leading: isArchived
                  ? const Icon(Icons.inventory_2_outlined, color: Colors.grey) // Hiện icon lưu trữ nếu bị xóa ảo
                  : Checkbox(
                value: isCompleted,
                onChanged: (val) async {
                  await dbHelper.updateTask(t["id"], val! ? 1 : 0);
                  loadTasks();
                },
              ),
              title: Text(
                t["title"],
                style: TextStyle(
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  color: isArchived ? Colors.grey : Colors.black,
                ),
              ),
              subtitle: Text(
                "${time.day}/${time.month}/${time.year} - ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
              ),
              trailing: isArchived
                  ? const Text("Đã lưu trữ", style: TextStyle(color: Colors.red, fontSize: 12))
                  : null,
            ),
          );
        },
      ),
    );
  }
}