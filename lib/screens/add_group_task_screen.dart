import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';

class AddGroupTaskScreen extends StatefulWidget {
  final String groupId;
  final String creatorName;

  const AddGroupTaskScreen({super.key, required this.groupId, required this.creatorName});

  @override
  State<AddGroupTaskScreen> createState() => _AddGroupTaskScreenState();
}

class _AddGroupTaskScreenState extends State<AddGroupTaskScreen> {
  final titleController = TextEditingController();
  final descController = TextEditingController();

  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  int remindBefore = 0;
  String repeatMode = "NONE";

  void saveGroupTask() async {
    if (titleController.text.isEmpty || selectedDate == null || selectedTime == null) return;

    DateTime finalDate = DateTime(
      selectedDate!.year, selectedDate!.month, selectedDate!.day,
      selectedTime!.hour, selectedTime!.minute,
    );

    // 1. Lưu vào Firestore của Nhóm
    DocumentReference docRef = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('tasks')
        .add({
      'title': titleController.text.trim(),
      'description': descController.text.trim(),
      'datetime': finalDate.toIso8601String(),
      'isCompleted': false,
      'remindBeforeMins': remindBefore,
      'repeatMode': repeatMode,
      'createdBy': widget.creatorName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Tự động lấy số ID từ chuỗi String của Firestore để cài chuông cục bộ
    int localId = docRef.id.hashCode & 0x7FFFFFFF;

    // 3. Cài chuông chính
    if (repeatMode == "NONE") {
      await NotificationService().scheduleNotification(localId, "Nhóm: ${titleController.text}", finalDate, description: descController.text);
    } else {
      await NotificationService().scheduleRepeatingNotification(localId, "Nhóm: ${titleController.text}", finalDate, repeat: repeatMode, description: descController.text);
    }

    // 4. Cài chuông báo trước
    if (remindBefore > 0) {
      DateTime remindTime = finalDate.subtract(Duration(minutes: remindBefore));
      if (remindTime.isAfter(DateTime.now())) {
        if (repeatMode == "NONE") {
          await NotificationService().scheduleNotification(localId * 10 + 1, "Sắp tới (Nhóm): ${titleController.text}", remindTime, description: descController.text);
        } else {
          await NotificationService().scheduleRepeatingNotification(localId * 10 + 1, "Sắp tới (Nhóm): ${titleController.text}", remindTime, repeat: repeatMode, description: descController.text);
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Thêm lịch Nhóm"), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: "Tiêu đề công việc")),
              TextField(controller: descController, decoration: const InputDecoration(labelText: "Ghi chú")),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(selectedDate == null ? "Chọn ngày" : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.calendar_today, color: Colors.blue), onPressed: () async {
                    var d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                    if (d != null) setState(() => selectedDate = d);
                  })
                ],
              ),
              Row(
                children: [
                  Text(selectedTime == null ? "Chọn giờ" : selectedTime!.format(context)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.access_time, color: Colors.orange), onPressed: () async {
                    var t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (t != null) setState(() => selectedTime = t);
                  })
                ],
              ),
              const SizedBox(height: 10), const Divider(), const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Nhắc trước:"),
                  DropdownButton<int>(
                    value: remindBefore,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("Không báo")),
                      DropdownMenuItem(value: 5, child: Text("5 phút")),
                      DropdownMenuItem(value: 30, child: Text("30 phút")),
                      DropdownMenuItem(value: 60, child: Text("1 giờ")),
                    ],
                    onChanged: (v) => setState(() => remindBefore = v!),
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
                    onChanged: (v) => setState(() => repeatMode = v!),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: saveGroupTask,
                child: const Text("TẠO LỊCH NHÓM", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }
}