import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeminiService {
  static Future<List<Map<String, dynamic>>?> chatAndAct(String input, {String groupContext = "", String currentScreen = "personal"}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');

    if (apiKey == null || apiKey.isEmpty) {
      return [{"type": "error", "message": "Bạn chưa cấu hình API Key. Vui lòng vào mục Hồ Sơ để cài đặt."}];
    }

    final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=$apiKey";
    String now = DateTime.now().toIso8601String();

    String locationContext = currentScreen == "personal"
        ? "Người dùng đang ở KHÔNG GIAN CÁ NHÂN. Nếu họ yêu cầu tạo lịch mà không nói rõ là cho nhóm nào, hãy MẶC ĐỊNH tạo lịch CÁ NHÂN."
        : "Người dùng đang ở TRONG MỘT NHÓM CỤ THỂ (ID nhóm sẽ được cung cấp nếu họ có quyền). Nếu họ yêu cầu tạo lịch, hãy ưu tiên tạo lịch cho nhóm này trừ khi họ yêu cầu khác.";

    final systemInstruction = """
Bạn là AI Trợ lý Quản lý Công việc thông minh và thân thiện. Hiện tại: $now.
$locationContext

Dưới đây là danh sách các Nhóm mà người dùng đang có quyền Quản trị:
$groupContext

HƯỚNG DẪN XỬ LÝ:
1. GIAO TIẾP THÔNG THƯỜNG: Trả lời tự nhiên, thân thiện bằng văn bản.
2. LỊCH CÁ NHÂN: "create", "update", "delete_mass".
3. LỊCH NHÓM: BẮT BUỘC dùng action "create_group_task". BẠN PHẢI điền chính xác "groupId" dựa vào danh sách trên. Nếu người dùng yêu cầu tạo lịch cho nhóm không có trong danh sách, KHÔNG ĐƯỢC GỌI HÀM, hãy trả lời bằng văn bản báo cho họ biết họ không có quyền hoặc sai tên nhóm.

QUY ƯỚC DỮ LIỆU: Lặp lại (NONE, DAILY, WEEKLY). Thứ 2 = 1, Chủ nhật = 7.
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
                  "description": "Chỉ gọi hàm này khi cần Tạo, Sửa, Xóa Hàng Loạt hoặc Tạo Lịch Nhóm.",
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
                            "deleteCondition": {"type": "STRING"},
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

      // ====================================================
      // 🔥 CÁC LỚP BẢO VỆ CHỐNG SẬP (NULL CRASH)
      // ====================================================

      // 1. Kiểm tra Server Google có báo lỗi không (Lỗi hàm, quá tải, API...)
      if (data.containsKey("error")) {
        String errorMsg = data["error"]["message"] ?? "Lỗi không xác định.";
        return [{"type": "error", "message": "Google từ chối: $errorMsg"}];
      }

      // 2. Kiểm tra AI có trả về kết quả không
      if (data["candidates"] == null || (data["candidates"] as List).isEmpty) {
        return [{"type": "error", "message": "AI từ chối trả lời (Có thể câu lệnh vi phạm an toàn)."}];
      }

      // 3. Kiểm tra nội dung có bị rỗng không
      var content = data["candidates"][0]["content"];
      if (content == null || content["parts"] == null || (content["parts"] as List).isEmpty) {
        return [{"type": "error", "message": "Nội dung trả về bị rỗng."}];
      }

      // ====================================================

      final parts = content["parts"];
      final firstPart = parts[0] as Map<String, dynamic>;

      // Nếu AI gọi thao tác xử lý lịch
      if (firstPart.containsKey("functionCall")) {
        final args = firstPart["functionCall"]["args"] ?? {};
        List<Map<String, dynamic>> results = [];

        if (args.containsKey("tasks") && args["tasks"] != null) {
          for (var item in args["tasks"]) {
            results.add({
              "type": "action",
              "action": item["action"],
              "title": item["title"],
              "description": item["description"],
              "datetime": item["datetime"],
              "remindBeforeMins": item["remindBeforeMins"],
              "repeatMode": item["repeatMode"],
              "deleteCondition": item["deleteCondition"],
              "groupId": item["groupId"],
              "targetTitles": item["targetTitles"] != null ? List<String>.from(item["targetTitles"]) : null,
            });
          }
          return results;
        }
      }

      // Nếu AI chỉ trò chuyện bình thường
      return [{"type": "text", "message": firstPart["text"] ?? "Tôi chưa hiểu ý bạn, bạn nói lại nhé."}];

    } catch (e) {
      return [{"type": "error", "message": "❌ Lỗi hệ thống: $e"}];
    }
  }
}