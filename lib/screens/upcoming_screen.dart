import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class UpcomingScreen extends StatefulWidget {
  const UpcomingScreen({super.key});
  @override
  State<UpcomingScreen> createState() => UpcomingScreenState();
}

class UpcomingScreenState extends State<UpcomingScreen> {
  final DBHelper dbHelper = DBHelper();
  DateTime selectedDay = DateTime.now();
  DateTime focusedDay = DateTime.now();

  List<Map<String, dynamic>> allTasks = [];
  List<Map<String, dynamic>> filteredTasks = [];
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
      allTasks = data;
      highlightTaskId = highlightId;
    });
    filterTasks();

    if (highlightId != null) {
      await Future.delayed(const Duration(milliseconds: 300));
      int index = filteredTasks.indexWhere((t) => t["id"] == highlightId);

      if (index != -1 && _scrollController.hasClients) {
        _scrollController.animateTo(
          index * 80.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => highlightTaskId = null);
        });
      }
    }
  }

  void filterTasks() {
    filteredTasks = allTasks.where((t) {
      DateTime time = DateTime.parse(t["datetime"]);
      return time.year == selectedDay.year && time.month == selectedDay.month && time.day == selectedDay.day;
    }).toList();
  }

  bool hasTask(DateTime day) {
    return allTasks.any((t) {
      DateTime time = DateTime.parse(t["datetime"]);
      return time.year == day.year && time.month == day.month && time.day == day.day;
    });
  }

  // 🔥 HÀM ẨN LỊCH NHÓM
  void hideGroupTask(Map task) async {
    await dbHelper.hideGroupTask(task["id"].toString());
    loadTasks();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Đã ẩn công việc nhóm này khỏi danh sách cá nhân!")),
    );
  }

  void deleteTask(Map task) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Xóa task"),
        content: Text("Bạn có chắc muốn xóa \"${task["title"]}\"?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Xóa")),
        ],
      ),
    );

    if (confirm != true) return;

    int id = task["id"];
    await NotificationService().cancelTask(id);

    bool isCompleted = task["isCompleted"] == 1;
    if (isCompleted) {
      await dbHelper.archiveTask(id);
    } else {
      await dbHelper.deleteTask(id);
    }

    loadTasks();

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(isCompleted ? "Đã lưu trữ ${task["title"]}" : "Đã xóa ${task["title"]}"),
        action: SnackBarAction(
          label: "Hoàn tác",
          onPressed: () async {
            if (isCompleted) {
              await dbHelper.unarchiveTask(id);
            } else {
              await dbHelper.insertTask(Map<String, dynamic>.from(task));
            }
            DateTime time = DateTime.parse(task["datetime"]);
            await NotificationService().scheduleNotification(id, task["title"], time, description: task["description"]);
            loadTasks();
          },
        ),
      ),
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
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            var d = await showDatePicker(context: context, initialDate: editSelectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                            if (d != null) setModalState(() => editSelectedDate = d);
                          },
                        )
                      ],
                    ),
                    Row(
                      children: [
                        Text(editSelectedTime.format(context)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.access_time),
                          onPressed: () async {
                            var t = await showTimePicker(context: context, initialTime: editSelectedTime);
                            if (t != null) setModalState(() => editSelectedTime = t);
                          },
                        )
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Nhắc trước:"),
                        DropdownButton<int>(
                          value: remindBefore,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text("Không báo trước")),
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

                        if (!mounted) return;
                        Navigator.pop(context);

                        setState(() {
                          selectedDay = finalDate;
                          focusedDay = finalDate;
                        });

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
    return Scaffold(
      appBar: AppBar(title: const Text("Upcoming")),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            focusedDay: focusedDay,
            selectedDayPredicate: (day) => isSameDay(day, selectedDay),
            onDaySelected: (selected, focused) {
              setState(() {
                selectedDay = selected;
                focusedDay = focused;
              });
              filterTasks();
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                bool has = hasTask(day);
                return Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: has ? Colors.red.withValues(alpha: 0.3) : null,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text("${day.day}"),
                );
              },
            ),
          ),
          Expanded(
            child: filteredTasks.isEmpty
                ? const Center(child: Text("Không có task"))
                : ListView.builder(
              controller: _scrollController,
              itemCount: filteredTasks.length,
              itemBuilder: (_, i) {
                final t = filteredTasks[i];
                DateTime time = DateTime.parse(t["datetime"]);
                var id = t["id"];
                String desc = t["description"] ?? "";
                bool isGroupTask = t["isGroupTask"] == true;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  color: getItemColor(id),
                  child: ListTile(
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
                            Text("${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}"),
                            if (t["repeatMode"] == 'DAILY' || t["repeatMode"] == 'WEEKLY')
                              const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.repeat, size: 14, color: Colors.grey)),
                            if (t["remindBeforeMins"] != null && t["remindBeforeMins"] > 0)
                              const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.notifications_active, size: 14, color: Colors.orange))
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
                        : IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => deleteTask(t),
                    ),
                    onTap: isGroupTask ? null : () => editTask(t),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}