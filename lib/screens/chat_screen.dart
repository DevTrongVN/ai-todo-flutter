import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/db_helper.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final DBHelper dbHelper = DBHelper();

  List<Map<String, dynamic>> messages = [];
  bool isLoading = false;

  // ================= CÁC HÀM TIỆN ÍCH HỖ TRỢ XÓA =================
  bool _checkDeleteMatch(Map<String, dynamic> t, String condition, List<String>? targetTitles, DateTime now) {
    if (t["datetime"] == null) return false;
    DateTime tTime = DateTime.parse(t["datetime"]);

    // SQLite dùng 1/0, Firestore dùng true/false
    bool isCompleted = t["isCompleted"] == 1 || t["isCompleted"] == true;
    bool isArchived = t["isArchived"] == 1 || t["isArchived"] == true;
    String repeat = t["repeatMode"]?.toString() ?? "NONE";

    if (condition == "all") return true;
    if (condition == "completed") return (isCompleted || isArchived);
    if (condition == "pending") return (!isCompleted && !isArchived);
    if (condition == "past") return (tTime.isBefore(now) && repeat == "NONE");

    if (condition == "list_titles" && targetTitles != null) {
      String taskTitle = t["title"].toString().toLowerCase().trim();
      for (var sTitle in targetTitles) {
        if (taskTitle.contains(sTitle.toLowerCase().trim())) return true;
      }
    }
    return false;
  }

  String _formatTime(String isoTime) {
    if (isoTime.isEmpty) return "";
    DateTime time = DateTime.parse(isoTime);
    return "${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}";
  }
  // ===============================================================

  void sendMessage() async {
    String text = controller.text;
    if (text.isEmpty) return;

    setState(() {
      messages.add({"text": text, "isUser": true, "hasUndo": false});
      isLoading = true;
    });
    controller.clear();

    // ==========================================
    // 🔥 TIÊM NGỮ CẢNH: DANH SÁCH NHÓM
    // ==========================================
    String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    String groupContext = "";

    if (myUid.isNotEmpty) {
      try {
        var groupsQuery = await FirebaseFirestore.instance
            .collection('groups')
            .where('members', arrayContains: myUid)
            .get();

        for (var doc in groupsQuery.docs) {
          var data = doc.data();
          Map<String, dynamic> roles = (data['roles'] as Map<String, dynamic>?) ?? {};
          String role = roles[myUid] ?? 'member';

          if (role == 'admin' || role == 'co-admin') {
            String groupName = data['name'] ?? "Nhóm không tên";
            groupContext += "- Tên nhóm: '$groupName' | groupId: '${doc.id}'\n";
          }
        }
      } catch (e) {
        print("Lỗi lấy danh sách nhóm: $e");
      }
    }

    if (groupContext.isEmpty) {
      groupContext = "Người dùng hiện KHÔNG CÓ QUYỀN Admin/Phó nhóm ở bất kỳ nhóm nào. KHÔNG ĐƯỢC phép tạo lịch nhóm.";
    }

    final results = await GeminiService.chatAndAct(text, groupContext: groupContext, currentScreen: "personal");

    setState(() {
      isLoading = false;
    });

    if (results == null || results.isEmpty) {
      addBot("❌ Hệ thống đang bận hoặc có lỗi kết nối.");
      return;
    }

    // ==========================================
    // 🔥 XỬ LÝ KẾT QUẢ TỪ AI
    // ==========================================
    for (var result in results) {
      if (result["type"] == "error") {
        addBot(result["message"] ?? "❌ Có lỗi xảy ra.");
      } else if (result["type"] == "text") {
        addBot(result["message"]);
      } else if (result["type"] == "action") {
        try {
          String action = result["action"] ?? "";

          // ================= TẠO LỊCH NHÓM =================
          if (action == "create_group_task") {
            String title = result["title"] ?? "Việc không tên";
            String groupId = result["groupId"]?.toString() ?? "";

            if (groupId.isEmpty) {
              addBot("⚠️ Vui lòng nói rõ bạn muốn tạo lịch cho nhóm nào.");
              continue;
            }

            if (result["datetime"] == null) {
              addBot("⚠️ Vui lòng cung cấp thời gian cho công việc.");
              continue;
            }

            DateTime parsed = DateTime.parse(result["datetime"]);
            DateTime time = DateTime(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute);
            String repeatMode = result["repeatMode"]?.toString() ?? "NONE";

            if (time.isBefore(DateTime.now())) {
              if (repeatMode == "DAILY") time = time.add(const Duration(days: 1));
              else if (repeatMode == "WEEKLY") time = time.add(const Duration(days: 7));
              else time = DateTime.now().add(const Duration(seconds: 5));
            }

            int? remindMins;
            if (result["remindBeforeMins"] != null) remindMins = int.tryParse(result["remindBeforeMins"].toString());

            User? u = FirebaseAuth.instance.currentUser;
            String myName = (u?.displayName?.isNotEmpty == true) ? u!.displayName! : "AI Trợ lý";
            String description = result["description"]?.toString() ?? "";

            DocumentReference docRef = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').add({
              'title': title,
              'description': description,
              'datetime': time.toIso8601String(),
              'isCompleted': false,
              'remindBeforeMins': remindMins,
              'repeatMode': repeatMode,
              'createdBy': myName,
              'createdAt': FieldValue.serverTimestamp(),
            });

            int localId = docRef.id.hashCode & 0x7FFFFFFF;

            if (repeatMode == "NONE") {
              await NotificationService().scheduleNotification(localId, "Nhóm: $title", time, description: description);
            } else {
              await NotificationService().scheduleRepeatingNotification(localId, "Nhóm: $title", time, repeat: repeatMode, description: description);
            }

            if (remindMins != null && remindMins > 0) {
              DateTime remindTime = time.subtract(Duration(minutes: remindMins));
              if (remindTime.isAfter(DateTime.now())) {
                if (repeatMode == "NONE") await NotificationService().scheduleNotification(localId * 10 + 1, "Sắp tới (Nhóm): $title", remindTime, description: description);
                else await NotificationService().scheduleRepeatingNotification(localId * 10 + 1, "Sắp tới (Nhóm): $title", remindTime, repeat: repeatMode, description: description);
              }
            }

            FirebaseFirestore.instance.collection('groups').doc(groupId).collection('messages').add({
              'text': "🤖 AI Trợ lý đã tự động thêm lịch: $title",
              'isSystem': true,
              'timestamp': FieldValue.serverTimestamp(),
            });

            addBot("✅ Đã lên lịch nhóm: \"$title\".");
          }

          // ================= TẠO LỊCH CÁ NHÂN =================
          else if (action == "create") {
            String title = result["title"] ?? "Việc không tên";

            if (result["datetime"] == null) {
              addBot("⚠️ Lịch cá nhân cần có thời gian. Hãy cho tôi biết thời gian nhé.");
              continue;
            }

            DateTime parsed = DateTime.parse(result["datetime"]);
            DateTime time = DateTime(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute);
            String repeatMode = result["repeatMode"]?.toString() ?? "NONE";
            String description = result["description"]?.toString() ?? "";

            if (time.isBefore(DateTime.now())) {
              if (repeatMode == "DAILY") time = time.add(const Duration(days: 1));
              else if (repeatMode == "WEEKLY") time = time.add(const Duration(days: 7));
              else time = DateTime.now().add(const Duration(seconds: 5));
            }

            int? remindMins;
            if (result["remindBeforeMins"] != null) remindMins = int.tryParse(result["remindBeforeMins"].toString());

            int id = await dbHelper.insertTask({
              "title": title,
              "description": description,
              "datetime": time.toIso8601String(),
              "isCompleted": 0,
              "remindBeforeMins": remindMins,
              "repeatMode": repeatMode,
            });

            if (repeatMode == "NONE") {
              await NotificationService().scheduleNotification(id, title, time, description: description);
            } else {
              await NotificationService().scheduleRepeatingNotification(id, title, time, repeat: repeatMode, description: description);
            }

            if (remindMins != null && remindMins > 0) {
              DateTime remindTime = time.subtract(Duration(minutes: remindMins));
              if (remindTime.isAfter(DateTime.now())) {
                if (repeatMode == "NONE") await NotificationService().scheduleNotification(id * 10 + 1, "Sắp tới: $title", remindTime, description: description);
                else await NotificationService().scheduleRepeatingNotification(id * 10 + 1, "Sắp tới: $title", remindTime, repeat: repeatMode, description: description);
              }
            }

            addBot("✅ Đã lên lịch cá nhân: \"$title\" lúc ${time.hour}:${time.minute.toString().padLeft(2, '0')}.");
          }

          // ================= UPDATE CÁ NHÂN =================
          else if (action == "update") {
            String title = result["title"] ?? "";
            if (title.isEmpty || result["datetime"] == null) continue;

            DateTime parsed = DateTime.parse(result["datetime"]);
            DateTime newTime = DateTime(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute);
            if (newTime.isBefore(DateTime.now())) newTime = DateTime.now().add(const Duration(seconds: 5));

            final tasks = await dbHelper.getTasks();
            bool found = false;
            String searchTitle = title.toLowerCase().trim();

            for (var t in tasks) {
              String taskTitle = t["title"].toString().toLowerCase().trim();
              if (taskTitle.contains(searchTitle) || searchTitle.contains(taskTitle)) {
                await dbHelper.updateTaskDetails(t["id"], title, newTime.toIso8601String());
                await NotificationService().scheduleNotification(t["id"], title, newTime);
                found = true;
              }
            }

            if (found) addBot("🔄 Đã dời lịch cá nhân \"$title\" sang ${newTime.hour}:${newTime.minute.toString().padLeft(2, '0')}.");
            else addBot("⚠️ Tôi không tìm thấy công việc \"$title\" để dời lịch.");
          }

          // ================= XÓA HÀNG LOẠT (CẢ CÁ NHÂN VÀ NHÓM) =================
          else if (action == "delete_mass" || action == "delete") {
            String condition = result["deleteCondition"]?.toString() ?? "list_titles";
            String? targetGroupId = result["groupId"]?.toString();
            List<String>? targetTitles;

            if (result["targetTitles"] != null) {
              targetTitles = List<String>.from(result["targetTitles"]);
            }
            if (action == "delete" && result["title"] != null) {
              condition = "list_titles";
              targetTitles = [result["title"].toString()];
            }

            List<Map<String, dynamic>> tasksToDelete = [];
            String reportDetails = "";
            DateTime now = DateTime.now();

            if (targetGroupId != null && targetGroupId.isNotEmpty) {
              // 🔥 TRƯỜNG HỢP 1: XÓA TRONG NHÓM
              var groupDoc = await FirebaseFirestore.instance.collection('groups').doc(targetGroupId).get();
              String groupName = groupDoc.data()?['name'] ?? "Nhóm";

              var groupTasksQuery = await FirebaseFirestore.instance
                  .collection('groups')
                  .doc(targetGroupId)
                  .collection('tasks')
                  .get();

              for (var doc in groupTasksQuery.docs) {
                var t = doc.data();
                bool match = _checkDeleteMatch(t, condition, targetTitles, now);
                if (match) {
                  tasksToDelete.add({...t, "id": doc.id, "isGroup": true, "groupId": targetGroupId});
                  reportDetails += "\n📌 [$groupName] ${t['title']} (${_formatTime(t['datetime'])})";

                  // Xóa Local Notification của task nhóm
                  int localId = doc.id.hashCode & 0x7FFFFFFF;
                  await NotificationService().cancelTask(localId);
                  // Xóa trên Firestore
                  await doc.reference.delete();
                }
              }

              if (tasksToDelete.isNotEmpty) {
                FirebaseFirestore.instance.collection('groups').doc(targetGroupId).collection('messages').add({
                  'text': "🤖 AI Trợ lý đã dọn dẹp ${tasksToDelete.length} lịch trình.",
                  'isSystem': true,
                  'timestamp': FieldValue.serverTimestamp(),
                });
              }

            } else {
              // 🏠 TRƯỜNG HỢP 2: XÓA CÁ NHÂN (SQLITE)
              final allLocalTasks = await dbHelper.getAllTasks();
              for (var t in allLocalTasks) {
                bool match = _checkDeleteMatch(t, condition, targetTitles, now);
                if (match) {
                  tasksToDelete.add({...t, "isGroup": false});
                  reportDetails += "\n👤 [Cá nhân] ${t['title']} (${_formatTime(t['datetime'])})";
                  await NotificationService().cancelTask(t["id"]);
                  await dbHelper.deleteTask(t["id"]);
                }
              }
            }

            if (tasksToDelete.isEmpty) {
              addBot("⚠️ Không tìm thấy lịch trình nào phù hợp để xóa.");
              continue;
            }

            setState(() {
              messages.add({
                "text": "🗑 **Đã xóa ${tasksToDelete.length} lịch trình:**$reportDetails",
                "isUser": false,
                "hasUndo": true,
                "deletedTasks": tasksToDelete
              });
            });
          }

        } catch (e) {
          print("LỖI XỬ LÝ DỮ LIỆU CỦA 1 TASK: $e");
          addBot("❌ Lỗi khi xử lý công việc. (Chi tiết: $e)");
        }
      }
    }
  }

  // ================= HÀM HOÀN TÁC (HỖ TRỢ CẢ NHÓM LẪN CÁ NHÂN) =================
  void undoTasks(int messageIndex) async {
    Map<String, dynamic> msg = messages[messageIndex];
    List<dynamic> deletedTasks = msg["deletedTasks"];

    for (var t in deletedTasks) {
      Map<String, dynamic> taskToRestore = Map<String, dynamic>.from(t);
      bool isGroup = taskToRestore["isGroup"] == true;
      String? groupId = taskToRestore["groupId"];

      // Xóa các cờ tạm trước khi lưu vào DB
      taskToRestore.remove("isGroup");
      taskToRestore.remove("groupId");

      int notificationId;

      if (isGroup && groupId != null) {
        // PHỤC HỒI LÊN FIRESTORE
        String docId = taskToRestore["id"].toString();
        taskToRestore.remove("id");
        await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').doc(docId).set(taskToRestore);
        notificationId = docId.hashCode & 0x7FFFFFFF;
      } else {
        // PHỤC HỒI LÊN SQLITE
        await dbHelper.insertTask(taskToRestore);
        notificationId = taskToRestore["id"];
      }

      // CÀI LẠI CHUÔNG
      if (taskToRestore["datetime"] != null) {
        DateTime time = DateTime.parse(taskToRestore["datetime"]);
        String repeatMode = taskToRestore["repeatMode"]?.toString() ?? "NONE";
        int remindMins = taskToRestore["remindBeforeMins"] ?? 0;
        String titlePrefix = isGroup ? "Nhóm: " : "";

        if (time.isAfter(DateTime.now()) || repeatMode != "NONE") {
          if (repeatMode == "NONE") {
            await NotificationService().scheduleNotification(notificationId, "$titlePrefix${taskToRestore['title']}", time, description: taskToRestore["description"]);
          } else {
            await NotificationService().scheduleRepeatingNotification(notificationId, "$titlePrefix${taskToRestore['title']}", time, repeat: repeatMode, description: taskToRestore["description"]);
          }

          if (remindMins > 0) {
            DateTime remindTime = time.subtract(Duration(minutes: remindMins));
            if (remindTime.isAfter(DateTime.now())) {
              await NotificationService().scheduleNotification(notificationId * 10 + 1, "Sắp tới: ${taskToRestore['title']}", remindTime, description: taskToRestore["description"]);
            }
          }
        }
      }
    }

    setState(() {
      messages[messageIndex]["hasUndo"] = false;
      messages[messageIndex]["text"] += "\n\n✅ Đã hoàn tác thành công!";
    });
  }

  void addBot(String text) {
    setState(() {
      messages.add({"text": text, "isUser": false, "hasUndo": false});
    });
  }

  Widget bubble(int index) {
    Map msg = messages[index];
    bool isUser = msg["isUser"];

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg["text"],
              style: TextStyle(fontSize: 15, color: isUser ? Colors.white : Colors.black87),
            ),
            if (msg["hasUndo"] == true) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green,
                    elevation: 0,
                    side: const BorderSide(color: Colors.green),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text("Hoàn tác"),
                onPressed: () => undoTasks(index),
              )
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Trợ lý AI 🤖"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              itemCount: messages.length,
              itemBuilder: (_, i) => bubble(i),
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text("AI đang suy nghĩ...", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: "VD: Xóa lịch đã xong trong nhóm Học Toán...",
                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: sendMessage,
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}