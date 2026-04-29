import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../database/db_helper.dart';

class NotificationService {
  static final NotificationService _instance =
  NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  final DBHelper _dbHelper = DBHelper();

  bool _isInitialized = false;

  // 👉 CALLBACK mở app
  Function(int taskId)? onNotificationTap;

  // ================= INIT =================
  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,

      // 🔥 CLICK / ACTION HANDLER
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;

        if (payload == null) return;

        final data = jsonDecode(payload);
        int taskId = data["taskId"];

        // ================= SNOOZE =================
        if (response.actionId == 'snooze') {
          final newTime = DateTime.now().add(const Duration(minutes: 5));

          await scheduleNotification(
            taskId,
            data["title"],
            newTime,
            description: data["description"],
          );

          return;
        }

        // ================= DONE =================
        if (response.actionId == 'done') {
          await _dbHelper.updateTask(taskId, 1);

          // 🔥 cancel luôn noti
          await cancelTask(taskId);

          return;
        }

        // ================= CLICK NOTI =================
        if (response.actionId == null) {
          // 👉 mở đúng task
          if (onNotificationTap != null) {
            onNotificationTap!(taskId);
          }
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'todo_channel',
      'Todo Reminder',
      description: 'Nhắc việc Todo',
      importance: Importance.max,
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(channel);
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }

    _isInitialized = true;
  }

  // ================= UTIL =================
  int normalizeId(int id) {
    return id & 0x7fffffff;
  }

  // ================= CANCEL =================
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(normalizeId(id));
  }

  Future<void> cancelTask(int id) async {
    await init();

    final mainId = normalizeId(id);
    final remindId = normalizeId(id * 10 + 1);

    await _plugin.cancel(mainId);
    await _plugin.cancel(remindId);
  }

  // ================= REPEAT =================
  Future<void> scheduleRepeatingNotification(
      int id,
      String title,
      DateTime time, {
        String repeat = "NONE",
        String? description,
      }) async {
    await init();

    final payload = jsonEncode({
      "taskId": id,
      "title": title,
      "description": description,
    });

    final safeId = normalizeId(id);

    await _plugin.zonedSchedule(
      safeId,
      "Nhắc việc",
      title,
      tz.TZDateTime.from(time, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_channel',
          'Todo Reminder',
          channelDescription: 'Nhắc việc Todo',
          importance: Importance.max,
          priority: Priority.high,
          actions: [
            const AndroidNotificationAction('snooze', 'Hoãn 5p'),
            const AndroidNotificationAction('done', 'Hoàn thành'),
          ],
        ),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: repeat == "DAILY"
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // ================= NORMAL =================
  Future<void> scheduleNotification(
      int id,
      String title,
      DateTime time, {
        String? description,
      }) async {
    await init();

    if (time.isBefore(DateTime.now())) return;

    final payload = jsonEncode({
      "taskId": id,
      "title": title,
      "description": description,
    });

    final safeId = normalizeId(id);

    await _plugin.zonedSchedule(
      safeId,
      "Nhắc việc",
      title,
      tz.TZDateTime.from(time, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_channel',
          'Todo Reminder',
          channelDescription: 'Nhắc việc Todo',
          importance: Importance.max,
          priority: Priority.high,
          actions: [
            const AndroidNotificationAction('snooze', 'Hoãn 5p'),
            const AndroidNotificationAction('done', 'Hoàn thành'),
          ],
          styleInformation: BigTextStyleInformation(
            description ?? title,
            contentTitle: title,
            summaryText: "Ghi chú",
          ),
        ),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}