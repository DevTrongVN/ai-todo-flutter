import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DBHelper {
  static Database? _db;

  // Lấy UID của user hiện tại (Nếu có)
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  Future<Database> initDB() async {
    String path = join(await getDatabasesPath(), 'todo.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            description TEXT,
            datetime TEXT,
            isCompleted INTEGER,
            remindBeforeMins INTEGER,
            repeatMode TEXT,
            repeatDays TEXT,
            isArchived INTEGER DEFAULT 0,
            lastEditedAt TEXT, -- 🔥 2. THÊM CỘT NÀY
            lastEditedBy TEXT  -- 🔥 2. THÊM CỘT NÀY
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE tasks ADD COLUMN isArchived INTEGER DEFAULT 0");
          await db.execute("ALTER TABLE tasks ADD COLUMN lastEditedAt TEXT");
          await db.execute("ALTER TABLE tasks ADD COLUMN lastEditedBy TEXT");
        }
      },
    );
  }

  // 🔥 TẠO ID DẠNG SỐ AN TOÀN CHO CẢ SQLITE LẪN FIRESTORE (Dùng chung cho Chuông báo)
  int generateId() {
    return DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
  }

  Future<int> insertTask(Map<String, dynamic> task) async {
    Map<String, dynamic> newTask = Map.from(task);
    newTask['isArchived'] = 0;

    // Đảm bảo task luôn có ID số nguyên
    if (!newTask.containsKey('id') || newTask['id'] == null) {
      newTask['id'] = generateId();
    }
    int taskId = newTask['id'];

    if (uid != null) {
      // ☁️ LƯU LÊN CLOUD FIRESTORE
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(taskId.toString())
          .set(newTask);
    } else {
      // 📱 LƯU OFFLINE SQLITE
      final dbClient = await db;
      await dbClient.insert('tasks', newTask, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return taskId;
  }

  Future<List<Map<String, dynamic>>> getTasks() async {
    if (uid != null) {
      // ☁️ LẤY TỪ CLOUD
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .where('isArchived', isEqualTo: 0)
          .get();
      var list = snapshot.docs.map((doc) => doc.data()).toList();
      // Sắp xếp theo thời gian tại app để tránh lỗi Index của Firestore
      list.sort((a, b) => a['datetime'].toString().compareTo(b['datetime'].toString()));
      return list;
    } else {
      // 📱 LẤY TỪ OFFLINE
      final dbClient = await db;
      return await dbClient.query('tasks', where: "isArchived = 0", orderBy: "datetime ASC");
    }
  }

  Future<List<Map<String, dynamic>>> getAllTasks() async {
    if (uid != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .get();
      var list = snapshot.docs.map((doc) => doc.data()).toList();
      list.sort((a, b) => a['datetime'].toString().compareTo(b['datetime'].toString()));
      return list;
    } else {
      final dbClient = await db;
      return await dbClient.query('tasks', orderBy: "datetime ASC");
    }
  }

  Future<void> deleteTask(int id) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id.toString()).delete();
    } else {
      final dbClient = await db;
      await dbClient.delete('tasks', where: "id = ?", whereArgs: [id]);
    }
  }

  Future<void> archiveTask(int id) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id.toString()).update({"isArchived": 1});
    } else {
      final dbClient = await db;
      await dbClient.update('tasks', {"isArchived": 1}, where: "id = ?", whereArgs: [id]);
    }
  }

  Future<void> unarchiveTask(int id) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id.toString()).update({"isArchived": 0});
    } else {
      final dbClient = await db;
      await dbClient.update('tasks', {"isArchived": 0}, where: "id = ?", whereArgs: [id]);
    }
  }

  Future<void> updateTask(int id, int isCompleted) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id.toString()).update({"isCompleted": isCompleted});
    } else {
      final dbClient = await db;
      await dbClient.update('tasks', {"isCompleted": isCompleted}, where: "id = ?", whereArgs: [id]);
    }
  }

  // 🔥 HÀM MỚI: Cập nhật thông tin task (Hỗ trợ cả Cloud và Offline)
  Future<void> updateFullTask(int id, Map<String, dynamic> updatedData) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id.toString()).update(updatedData);
    } else {
      final dbClient = await db;
      await dbClient.update('tasks', updatedData, where: "id = ?", whereArgs: [id]);
    }
  }

  Future<void> updateTaskDetails(int id, String title, String datetime) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id.toString()).update({"title": title, "datetime": datetime});
    } else {
      final dbClient = await db;
      await dbClient.update('tasks', {"title": title, "datetime": datetime}, where: "id = ?", whereArgs: [id]);
    }
  }

  // 🔥 HÀM MA THUẬT: ĐỒNG BỘ DỮ LIỆU TỪ MÁY LÊN CLOUD KHI VỪA ĐĂNG NHẬP
  Future<void> syncLocalToCloud() async {
    if (uid == null) return;

    final dbClient = await db;
    final localTasks = await dbClient.query('tasks');

    if (localTasks.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (var task in localTasks) {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(task['id'].toString());
      batch.set(docRef, task);
    }
    await batch.commit();
    await dbClient.delete('tasks');
  }

  // 1. Hàm lưu ID của lịch nhóm bị ẩn vào hồ sơ User trên Firebase
  Future<void> hideGroupTask(String taskId) async {
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'hiddenGroupTasks': FieldValue.arrayUnion([taskId])
      }, SetOptions(merge: true));
    }
  }

  // 2. Hàm lấy TẤT CẢ công việc (Cá nhân + Nhóm) và tự động lọc bỏ các việc đã ẩn
  Future<List<Map<String, dynamic>>> getMixedTasks() async {
    List<Map<String, dynamic>> mixedList = [];

    // LẤY LỊCH CÁ NHÂN
    var personalTasks = await getTasks();
    for (var t in personalTasks) {
      mixedList.add({...t, 'isGroupTask': false});
    }

    // LẤY LỊCH NHÓM (Nếu đã đăng nhập)
    if (uid != null) {
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      List<dynamic> hiddenTasks = userDoc.data()?['hiddenGroupTasks'] ?? [];
      var groupsQuery = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: uid).get();

      for (var groupDoc in groupsQuery.docs) {
        String groupId = groupDoc.id;
        String groupName = groupDoc.data()['name'] ?? "Nhóm";

        var tasksQuery = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').get();

        for (var taskDoc in tasksQuery.docs) {
          if (!hiddenTasks.contains(taskDoc.id)) {
            var t = taskDoc.data();

            // 🔥 LỌC CỨNG: Nếu Lịch Nhóm đã lưu trữ -> Không cho ra ngoài màn hình chính!
            if (t['isArchived'] == true || t['isArchived'] == 1) continue;

            mixedList.add({
              ...t,
              'id': taskDoc.id,
              'isGroupTask': true,
              'groupId': groupId,
              'groupName': groupName,
              'isCompleted': (t['isCompleted'] == true || t['isCompleted'] == 1) ? 1 : 0,
            });
          }
        }
      }
    }

    mixedList.sort((a, b) => a['datetime'].toString().compareTo(b['datetime'].toString()));
    return mixedList;
  }

  // 🔥 HÀM MỚI (SỬ DỤNG CHO HỒ SƠ THỐNG KÊ): LẤY TẤT CẢ KỂ CẢ ĐÃ LƯU TRỮ
  Future<List<Map<String, dynamic>>> getAllMixedTasks() async {
    List<Map<String, dynamic>> mixedList = [];

    // Lấy toàn bộ lịch cá nhân (Cả đã lưu trữ)
    var personalTasks = await getAllTasks();
    for (var t in personalTasks) {
      mixedList.add({...t, 'isGroupTask': false});
    }

    if (uid != null) {
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      List<dynamic> hiddenTasks = userDoc.data()?['hiddenGroupTasks'] ?? [];
      var groupsQuery = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: uid).get();

      for (var groupDoc in groupsQuery.docs) {
        String groupId = groupDoc.id;
        String groupName = groupDoc.data()['name'] ?? "Nhóm";

        var tasksQuery = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').get();

        for (var taskDoc in tasksQuery.docs) {
          if (!hiddenTasks.contains(taskDoc.id)) {
            var t = taskDoc.data();

            // KHÔNG LỌC isArchived Ở ĐÂY ĐỂ ĐƯA VÀO BẢNG THỐNG KÊ
            mixedList.add({
              ...t,
              'id': taskDoc.id,
              'isGroupTask': true,
              'groupId': groupId,
              'groupName': groupName,
              'isCompleted': (t['isCompleted'] == true || t['isCompleted'] == 1) ? 1 : 0,
            });
          }
        }
      }
    }

    mixedList.sort((a, b) => a['datetime'].toString().compareTo(b['datetime'].toString()));
    return mixedList;
  }
}