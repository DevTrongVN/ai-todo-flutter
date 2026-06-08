import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';

class SocialService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. GỬI LỜI MỜI KẾT BẠN
  static Future<void> sendFriendRequest(String currentUserId, String currentUserName, String targetUid) async {
    await _db.collection('users').doc(targetUid).set({
      'friendRequests': FieldValue.arrayUnion([currentUserId])
    }, SetOptions(merge: true));

    await NotificationService().sendFriendRequestNotification(targetUid, currentUserName);
  }

  // 2. HỦY KẾT BẠN (ĐỒNG BỘ 2 CHIỀU)
  static Future<void> unfriend(String currentUserId, String targetUid) async {
    await _db.collection('users').doc(currentUserId).update({
      'friends': FieldValue.arrayRemove([targetUid])
    });
    await _db.collection('users').doc(targetUid).update({
      'friends': FieldValue.arrayRemove([currentUserId])
    });
  }

  // 3. CHẶN / BỎ CHẶN NGƯỜI DÙNG
  static Future<void> toggleBlockUser(String currentUserId, String targetUid, bool isCurrentlyBlocked) async {
    if (isCurrentlyBlocked) {
      await _db.collection('users').doc(currentUserId).update({
        'blockedUsers': FieldValue.arrayRemove([targetUid])
      });
    } else {
      await _db.collection('users').doc(currentUserId).update({
        'blockedUsers': FieldValue.arrayUnion([targetUid])
      });
      await unfriend(currentUserId, targetUid);
    }
  }

  // 🔥 4. DEEP DELETE: HỦY KẾT BẠN TOÀN BỘ DANH BẠ (FAIL-SAFE)
  static Future<void> unfriendAll(String currentUserId, List<dynamic> friendIds) async {
    for (String targetUid in friendIds) {
      try {
        await _db.collection('users').doc(targetUid).update({
          'friends': FieldValue.arrayRemove([currentUserId])
        });
      } catch (e) {
        debugPrint("Bỏ qua lỗi hủy kết bạn (Người dùng có thể đã xóa TK từ trước): $e");
      }
    }
  }

  // 🔥 5. DEEP DELETE: CÀN QUÉT CÁC NHÓM ĐÃ THAM GIA (FAIL-SAFE)
  static Future<void> processGroupsOnDelete(String currentUserId, String userName) async {
    try {
      var groups = await _db.collection('groups').where('members', arrayContains: currentUserId).get();

      for (var gDoc in groups.docs) {
        try {
          String groupId = gDoc.id;
          String role = gDoc.data()['roles']?[currentUserId] ?? 'member';

          if (role == 'admin') {
            try {
              final storageRef = FirebaseStorage.instance.ref().child('group_chat_images/$groupId');
              final listResult = await storageRef.listAll();
              for (var item in listResult.items) await item.delete();
            } catch(e) {}

            var tasks = await _db.collection('groups').doc(groupId).collection('tasks').get();
            for (var doc in tasks.docs) await doc.reference.delete();

            var msgs = await _db.collection('groups').doc(groupId).collection('messages').get();
            for (var doc in msgs.docs) await doc.reference.delete();

            await _db.collection('groups').doc(groupId).delete();
          } else {
            await _db.collection('groups').doc(groupId).update({
              'members': FieldValue.arrayRemove([currentUserId]),
              'roles.$currentUserId': FieldValue.delete()
            });
            await _db.collection('groups').doc(groupId).collection('messages').add({
              'text': "👋 $userName đã rời khỏi nhóm (Tài khoản đã xóa).",
              'isSystem': true, 'timestamp': FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          debugPrint("Bỏ qua lỗi xử lý nhóm $gDoc.id: $e");
        }
      }
    } catch (e) {
      debugPrint("Lỗi quét danh sách nhóm: $e");
    }
  }

  // 🔥 6. DEEP DELETE: XÓA TOÀN BỘ TIN NHẮN CÁ NHÂN (FAIL-SAFE)
  static Future<void> deleteAllPrivateChats(String currentUserId) async {
    try {
      var chats = await _db.collection('private_chats').get();
      for (var doc in chats.docs) {
        if (doc.id.contains(currentUserId)) {
          try {
            var msgs = await doc.reference.collection('messages').get();
            for (var msg in msgs.docs) await msg.reference.delete();
            await doc.reference.delete();
          } catch (e) {}
        }
      }
    } catch (e) {}
  }
}