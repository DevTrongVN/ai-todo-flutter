import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});
  @override
  State<InboxScreen> createState() => InboxScreenState();
}

class InboxScreenState extends State<InboxScreen> {
  final DBHelper dbHelper = DBHelper();
  List<Map<String, dynamic>> tasks = [];
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  final ScrollController _scrollController = ScrollController();
  dynamic highlightTaskId;

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  void loadTasks({dynamic highlightId}) async {
    // 🔥 LẤY HỖN HỢP CẢ LỊCH CÁ NHÂN VÀ NHÓM
    final data = await dbHelper.getMixedTasks();
    if (!mounted) return;
    setState(() {
      tasks = data;
      highlightTaskId = highlightId;
    });

    if (highlightId != null) {
      await Future.delayed(const Duration(milliseconds: 300));
      int index = tasks.indexWhere((t) => t["id"] == highlightId);

      if (index != -1 && _scrollController.hasClients) {
        _scrollController.animateTo(index * 80.0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => highlightTaskId = null);
        });
      }
    }
  }

  void deleteCompleted() async {
    for (var t in tasks) {
      // Bỏ qua lịch nhóm, chỉ dọn lịch cá nhân
      if (t["isCompleted"] == 1 && t["isGroupTask"] != true) {
        await NotificationService().cancelTask(t["id"]);
        await dbHelper.archiveTask(t["id"]);
      }
    }
    loadTasks();
  }

  // 🔥 HÀM ẨN LỊCH NHÓM
  void hideGroupTask(Map task) async {
    await dbHelper.hideGroupTask(task["id"].toString());
    loadTasks();
    messengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text("Đã ẩn công việc nhóm này khỏi danh sách cá nhân!")),
    );
  }

  void editTask(Map task) {
    TextEditingController titleController = TextEditingController(text: task["title"]);
    TextEditingController descController = TextEditingController(text: task["description"] ?? "");
    DateTime oldDate = DateTime.parse(task["datetime"]);
    DateTime editSelectedDate = oldDate;
    TimeOfDay editSelectedTime = TimeOfDay(hour: oldDate.hour, minute: oldDate.minute);
    int remindBefore = task["remindBeforeMins"] ?? 0;
    String repeatMode = task["repeatMode"] ?? "NONE";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Sửa task", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(controller: titleController, decoration: const InputDecoration(labelText: "Tiêu đề")),
                    TextField(controller: descController, decoration: const InputDecoration(labelText: "Ghi chú")),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text("${editSelectedDate.day}/${editSelectedDate.month}/${editSelectedDate.year}"),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.calendar_today), onPressed: () async {
                          var d = await showDatePicker(context: context, initialDate: editSelectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (d != null) setModalState(() => editSelectedDate = d);
                        })
                      ],
                    ),
                    Row(
                      children: [
                        Text(editSelectedTime.format(context)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.access_time), onPressed: () async {
                          var t = await showTimePicker(context: context, initialTime: editSelectedTime);
                          if (t != null) setModalState(() => editSelectedTime = t);
                        })
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Nhắc trước:"),
                        DropdownButton<int>(
                          value: remindBefore,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text("Không báo")),
                            DropdownMenuItem(value: 5, child: Text("5 phút")),
                            DropdownMenuItem(value: 10, child: Text("10 phút")),
                            DropdownMenuItem(value: 30, child: Text("30 phút")),
                            DropdownMenuItem(value: 60, child: Text("1 giờ")),
                          ],
                          onChanged: (v) => setModalState(() => remindBefore = v!),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Lặp lại:"),
                        DropdownButton<String>(
                          value: repeatMode,
                          items: const [
                            DropdownMenuItem(value: 'NONE', child: Text("Không lặp")),
                            DropdownMenuItem(value: 'DAILY', child: Text("Hằng ngày")),
                            DropdownMenuItem(value: 'WEEKLY', child: Text("Hằng tuần")),
                          ],
                          onChanged: (v) => setModalState(() => repeatMode = v!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleController.text.isEmpty) return;
                        int id = task["id"];
                        DateTime finalDate = DateTime(editSelectedDate.year, editSelectedDate.month, editSelectedDate.day, editSelectedTime.hour, editSelectedTime.minute);

                        await NotificationService().cancelTask(id);

                        final db = await dbHelper.db;
                        await db.update(
                          'tasks',
                          {
                            "title": titleController.text,
                            "description": descController.text,
                            "datetime": finalDate.toIso8601String(),
                            "remindBeforeMins": remindBefore,
                            "repeatMode": repeatMode,
                          },
                          where: "id = ?",
                          whereArgs: [id],
                        );

                        if (repeatMode == "NONE") {
                          await NotificationService().scheduleNotification(id, titleController.text, finalDate, description: descController.text);
                        } else {
                          await NotificationService().scheduleRepeatingNotification(id, titleController.text, finalDate, repeat: repeatMode, description: descController.text);
                        }

                        if (remindBefore > 0 && repeatMode == "NONE") {
                          DateTime remindTime = finalDate.subtract(Duration(minutes: remindBefore));
                          await NotificationService().scheduleNotification(id * 10 + 1, "Sắp tới: ${titleController.text}", remindTime, description: descController.text);
                        }

                        if (!context.mounted) return;
                        Navigator.pop(context);
                        loadTasks(highlightId: id);
                      },
                      child: const Text("Lưu"),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color getItemColor(dynamic id) {
    if (highlightTaskId == id) return Colors.yellow.withValues(alpha: 0.4);
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text("Inbox"), actions: [IconButton(icon: const Icon(Icons.delete_sweep), onPressed: deleteCompleted)]),
        body: ListView.builder(
          controller: _scrollController,
          itemCount: tasks.length,
          itemBuilder: (_, i) {
            final t = tasks[i];
            DateTime time = DateTime.parse(t["datetime"]);
            var id = t["id"];
            String desc = t["description"] ?? "";
            bool isGroupTask = t["isGroupTask"] == true;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              color: getItemColor(id),
              child: Dismissible(
                key: Key(id.toString()),
                direction: isGroupTask ? DismissDirection.none : DismissDirection.horizontal,
                background: Container(color: Colors.green),
                secondaryBackground: Container(color: Colors.red),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    await dbHelper.updateTask(id as int, 1);
                    loadTasks();
                    return false;
                  }
                  return true;
                },
                onDismissed: (_) async {
                  final deleted = Map<String, dynamic>.from(t);
                  await NotificationService().cancelTask(id as int);

                  bool isCompleted = t["isCompleted"] == 1;

                  if (isCompleted) {
                    await dbHelper.archiveTask(id);
                  } else {
                    await dbHelper.deleteTask(id);
                  }

                  loadTasks();

                  messengerKey.currentState?.showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 5),
                      content: Text(isCompleted ? "Đã lưu trữ ${t["title"]}" : "Đã xóa ${t["title"]}"),
                      action: SnackBarAction(
                        label: "Hoàn tác",
                        onPressed: () async {
                          if (isCompleted) {
                            await dbHelper.unarchiveTask(id);
                          } else {
                            await dbHelper.insertTask(deleted);
                          }
                          DateTime time = DateTime.parse(deleted["datetime"]);
                          await NotificationService().scheduleNotification(deleted["id"], deleted["title"], time, description: deleted["description"]);
                          loadTasks();
                        },
                      ),
                    ),
                  );
                },
                child: ListTile(
                  leading: Checkbox(
                      value: t["isCompleted"] == 1,
                      onChanged: isGroupTask ? null : (val) async {
                        await dbHelper.updateTask(id as int, val! ? 1 : 0);
                        loadTasks();
                      }
                  ),
                  title: Text(t["title"], style: TextStyle(decoration: t["isCompleted"] == 1 ? TextDecoration.lineThrough : null)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isGroupTask)
                        Container(
                          margin: const EdgeInsets.only(top: 4, bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.deepPurple.shade200)
                          ),
                          child: Text("👥 Nhóm: ${t['groupName']}", style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                        ),
                      Row(
                        children: [
                          Text("${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}"),
                          if (t["repeatMode"] == 'DAILY' || t["repeatMode"] == 'WEEKLY') const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.repeat, size: 14, color: Colors.grey)),
                          if (t["remindBeforeMins"] != null && t["remindBeforeMins"] > 0) const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.notifications_active, size: 14, color: Colors.orange))
                        ],
                      ),
                      if (desc.isNotEmpty) Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  trailing: isGroupTask
                      ? IconButton(
                    icon: const Icon(Icons.visibility_off, color: Colors.grey),
                    tooltip: "Ẩn lịch này",
                    onPressed: () => hideGroupTask(t),
                  )
                      : null,
                  onTap: isGroupTask ? null : () => editTask(t),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}