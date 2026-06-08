import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class GeminiService {
  // 🔥 LƯU RAM: 캐 (Cache) API Key để không phải tốn tiền gọi Firebase nhiều lần
  static String? _cachedApiKey;

  static Future<List<Map<String, dynamic>>?> chatAndAct(String input, {String groupContext = "", String currentScreen = "personal"}) async {

    // Chỉ lên Firebase lấy Key nếu RAM chưa có
    if (_cachedApiKey == null || _cachedApiKey!.isEmpty) {
      try {
        var doc = await FirebaseFirestore.instance.collection('app_config').doc('keys').get();
        if (doc.exists && doc.data() != null) {
          _cachedApiKey = doc.data()!['gemini_api_key'] ?? "";
        }
      } catch (e) {
        return [{"type": "error", "message": "Lỗi kết nối máy chủ AI."}];
      }
    }

    if (_cachedApiKey == null || _cachedApiKey!.isEmpty) {
      return [{"type": "error", "message": "Hệ thống AI đang bảo trì (Thiếu API Key)."}] ;
    }

    final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=$_cachedApiKey";
    String now = DateTime.now().toIso8601String();

    String locationContext = currentScreen == "personal"
        ? "Người dùng đang ở KHÔNG GIAN CÁ NHÂN. Mặc định tạo lịch Cá Nhân nếu họ không nhắc đến nhóm."
        : "Người dùng đang ở TRONG MỘT NHÓM. Mặc định tạo lịch Nhóm nếu họ không nói khác.";

    final systemInstruction = """
Bạn là AI Quản lý Lịch Trình (Cá nhân & Nhóm). Thời gian hiện tại: $now.
$locationContext

DANH SÁCH NHÓM CÓ QUYỀN ADMIN/PHÓ NHÓM (Chỉ được sửa/xóa/tạo ở đây):
$groupContext

HƯỚNG DẪN DÙNG HÀM:
1. Giao tiếp: Trả lời tự nhiên bằng text.
2. Lịch cá nhân: "create", "update", "delete". 
3. Lịch nhóm: "create_group_task", "update_group_task", "delete_group_task".
  - PHẢI điền chính xác "groupId" lấy từ danh sách trên.
  - Từ chối nếu họ yêu cầu thao tác nhóm không có trong danh sách.
4. Update/Delete: Cần truyền mảng `targetTitles` chứa các từ khóa trong tên lịch.
""";

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "system_instruction": {
            "parts": [{"text": systemInstruction}]
          },
          "contents": [
            {"role": "user", "parts": [{"text": input}]}
          ],
          "tools": [
            {
              "function_declarations": [
                {
                  "name": "manage_tasks",
                  "description": "Gọi để Tạo, Sửa, Xóa lịch Cá Nhân hoặc Nhóm.",
                  "parameters": {
                    "type": "OBJECT",
                    "properties": {
                      "tasks": {
                        "type": "ARRAY",
                        "items": {
                          "type": "OBJECT",
                          "properties": {
                            "action": {"type": "STRING"},
                            "title": {"type": "STRING"},
                            "description": {"type": "STRING"},
                            "datetime": {"type": "STRING"},
                            "remindBeforeMins": {"type": "NUMBER"},
                            "repeatMode": {"type": "STRING"},
                            "groupId": {"type": "STRING"},
                            "targetTitles": {
                              "type": "ARRAY",
                              "items": {"type": "STRING"}
                            }
                          },
                          "required": ["action"]
                        }
                      }
                    }
                  }
                }
              ]
            }
          ],
          "tool_config": {
            "function_calling_config": {"mode": "AUTO"}
          }
        }),
      );

      final data = jsonDecode(res.body);

      if (data.containsKey("error")) {
        return [{"type": "error", "message": "Google báo lỗi: ${data['error']['message']}"}];
      }

      final parts = data["candidates"][0]["content"]["parts"];
      final firstPart = parts[0] as Map<String, dynamic>;

      if (firstPart.containsKey("functionCall")) {
        final args = firstPart["functionCall"]["args"] ?? {};
        List<Map<String, dynamic>> results = [];
        if (args.containsKey("tasks")) {
          for (var item in args["tasks"]) {
            results.add({
              "type": "action",
              "action": item["action"],
              "title": item["title"],
              "description": item["description"],
              "datetime": item["datetime"],
              "remindBeforeMins": item["remindBeforeMins"],
              "repeatMode": item["repeatMode"],
              "groupId": item["groupId"],
              "targetTitles": item["targetTitles"] != null ? List<String>.from(item["targetTitles"]) : null,
            });
          }
          return results;
        }
      }

      return [{"type": "text", "message": firstPart["text"] ?? "Tôi chưa hiểu ý bạn."}];

    } catch (e) {
      return [{"type": "error", "message": "Lỗi hệ thống: $e"}];
    }
  }
}