import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final titleController = TextEditingController();
  final descController = TextEditingController();

  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  int remindBefore = 0; // phút

  final DBHelper dbHelper = DBHelper();

  void saveTask() async {
    if (titleController.text.isEmpty ||
        selectedDate == null ||
        selectedTime == null) return;

    DateTime finalDate = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );


    int id = await dbHelper.insertTask({
      "title": titleController.text,
      "description": descController.text,
      "datetime": finalDate.toIso8601String(),
      "isCompleted": 0,
      "remindBeforeMins": remindBefore,
    });


    await NotificationService().scheduleNotification(
      id,
      titleController.text,
      finalDate,
      description: descController.text,
    );


    if (remindBefore > 0) {
      DateTime remindTime = finalDate.subtract(
        Duration(minutes: remindBefore),
      );

      await NotificationService().scheduleNotification(
        id * 10 + 1,
        "Sắp tới: ${titleController.text}",
        remindTime,
        description: descController.text,
      );
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tạo Task")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Tiêu đề"),
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: "Ghi chú"),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Text(selectedDate == null
                    ? "Chọn ngày"
                    : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    var d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => selectedDate = d);
                  },
                )
              ],
            ),

            Row(
              children: [
                Text(selectedTime == null
                    ? "Chọn giờ"
                    : selectedTime!.format(context)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.access_time),
                  onPressed: () async {
                    var t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (t != null) setState(() => selectedTime = t);
                  },
                )
              ],
            ),

            const SizedBox(height: 10),

            DropdownButton<int>(
              value: remindBefore,
              items: const [
                DropdownMenuItem(value: 0, child: Text("Không báo trước")),
                DropdownMenuItem(value: 5, child: Text("5 phút")),
                DropdownMenuItem(value: 10, child: Text("10 phút")),
                DropdownMenuItem(value: 30, child: Text("30 phút")),
                DropdownMenuItem(value: 60, child: Text("1 giờ")),
              ],
              onChanged: (v) => setState(() => remindBefore = v!),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: saveTask,
              child: const Text("Lưu"),
            )
          ],
        ),
      ),
    );
  }
}