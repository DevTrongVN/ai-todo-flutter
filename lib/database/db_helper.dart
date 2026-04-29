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
      version: 2,
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
            isArchived INTEGER DEFAULT 0 
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE tasks ADD COLUMN isArchived INTEGER DEFAULT 0");
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
    final localTasks = await dbClient.query('tasks'); // Lấy hết việc offline

    if (localTasks.isEmpty) return; // Không có gì thì thôi

    final batch = FirebaseFirestore.instance.batch();
    for (var task in localTasks) {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(task['id'].toString());
      batch.set(docRef, task);
    }
    await batch.commit(); // Đẩy 1 phát lên mây

    // Đẩy xong thì xóa sạch SQLite để tránh hiện trùng 2 lần
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
    var personalTasks = await getTasks(); // Lấy từ SQLite hoặc Cloud cá nhân
    for (var t in personalTasks) {
      mixedList.add({...t, 'isGroupTask': false});
    }

    // LẤY LỊCH NHÓM (Nếu đã đăng nhập)
    if (uid != null) {
      // Đọc danh sách lịch nhóm đã bị ẩn của user này
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      List<dynamic> hiddenTasks = userDoc.data()?['hiddenGroupTasks'] ?? [];

      // Quét tất cả các nhóm người này tham gia
      var groupsQuery = await FirebaseFirestore.instance.collection('groups').where('members', arrayContains: uid).get();

      for (var groupDoc in groupsQuery.docs) {
        String groupId = groupDoc.id;
        String groupName = groupDoc.data()['name'] ?? "Nhóm";

        var tasksQuery = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').get();

        for (var taskDoc in tasksQuery.docs) {
          // Chỉ lấy những lịch CHƯA BỊ ẨN
          if (!hiddenTasks.contains(taskDoc.id)) {
            var t = taskDoc.data();
            mixedList.add({
              ...t,
              'id': taskDoc.id, // ID của Firestore là String
              'isGroupTask': true,
              'groupId': groupId,
              'groupName': groupName,
              // Đồng bộ kiểu dữ liệu isCompleted về dạng số 0/1 để UI không bị lỗi
              'isCompleted': (t['isCompleted'] == true || t['isCompleted'] == 1) ? 1 : 0,
            });
          }
        }
      }
    }

    // Sắp xếp lại toàn bộ theo thời gian từ sớm đến muộn
    mixedList.sort((a, b) => a['datetime'].toString().compareTo(b['datetime'].toString()));
    return mixedList;
  }
}