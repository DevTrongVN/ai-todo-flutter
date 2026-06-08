import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/social_service.dart';
import '../services/notification_service.dart';

class GroupInfoScreen extends StatefulWidget {
  final Map<String, dynamic> groupData;
  final String currentUserId;
  final String myName;
  final String myRole;

  const GroupInfoScreen({super.key, required this.groupData, required this.currentUserId, required this.myName, required this.myRole});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<Map<String, dynamic>> members = [];
  List<dynamic> myFriends = [];
  List<dynamic> myBlockedUsers = [];
  bool isLoading = true;
  bool isProcessing = false;

  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).snapshots().listen((myDoc) {
      if (mounted) {
        setState(() {
          myFriends = myDoc.data()?['friends'] ?? [];
          myBlockedUsers = myDoc.data()?['blockedUsers'] ?? [];
        });
      }
    });

    FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).snapshots().listen((doc) async {
      if (!doc.exists) return;
      var gData = doc.data()!;
      List<dynamic> memberIds = gData['members'] ?? [];
      Map<String, dynamic> roles = gData['roles'] ?? {};
      List<dynamic> mutedList = gData['muted'] ?? [];

      if (memberIds.isEmpty) return;
      var usersSnapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: memberIds).get();

      if (mounted) {
        setState(() {
          members = usersSnapshot.docs.map((d) => { ...d.data(), "uid": d.id, "role": roles[d.id] ?? 'member', "isMuted": mutedList.contains(d.id) }).toList();
          members.sort((a, b) {
            int rankA = a['role'] == 'admin' ? 0 : (a['role'] == 'co-admin' ? 1 : 2);
            int rankB = b['role'] == 'admin' ? 0 : (b['role'] == 'co-admin' ? 1 : 2);
            return rankA.compareTo(rankB);
          });
          isLoading = false;
        });
      }
    });
  }

  void _sendSystemMessage(String content) {
    FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).collection('messages').add({
      'text': content, 'isSystem': true, 'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _kickMember(String targetUid, String targetName) async {
    await FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).update({'members': FieldValue.arrayRemove([targetUid]), 'roles.$targetUid': FieldValue.delete()});
    _sendSystemMessage("👢 ${widget.myName} đã kick $targetName ra khỏi nhóm.");
  }

  void _leaveGroup() async {
    bool? confirm = await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Rời nhóm"), content: const Text("Bạn có chắc muốn rời nhóm? Lịch trình của nhóm này sẽ không còn thông báo trên máy bạn nữa."), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), onPressed: () => Navigator.pop(context, true), child: const Text("Rời đi", style: TextStyle(color: Colors.white)))]));

    if (confirm == true) {
      if (mounted) setState(() => isProcessing = true);
      String groupId = widget.groupData['id'];

      await FirebaseFirestore.instance.collection('groups').doc(groupId).update({'members': FieldValue.arrayRemove([widget.currentUserId]), 'roles.${widget.currentUserId}': FieldValue.delete()});
      _sendSystemMessage("👋 ${widget.myName} đã rời khỏi nhóm.");

      var tasksSnapshot = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').get();
      for (var doc in tasksSnapshot.docs) {
        await NotificationService().cancelTask(doc.id.hashCode & 0x7FFFFFFF);
      }

      await FirebaseMessaging.instance.unsubscribeFromTopic('group_$groupId');

      if (mounted) {
        setState(() => isProcessing = false);
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }
  }

  void _toggleMute(String targetUid, String targetName, bool isMuted) async {
    await FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).update({'muted': isMuted ? FieldValue.arrayRemove([targetUid]) : FieldValue.arrayUnion([targetUid])});
    _sendSystemMessage("🔇 ${widget.myName} đã ${isMuted ? "mở khóa chat cho" : "cấm chat"} $targetName.");
  }

  void _changeRole(String targetUid, String targetName, String newRole) async {
    await FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).update({'roles.$targetUid': newRole});
    _sendSystemMessage("⭐ ${widget.myName} đã đặt $targetName làm ${newRole == 'co-admin' ? "Phó nhóm" : "Thành viên"}.");
  }

  void _deleteGroup() async {
    bool? confirm = await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Giải tán nhóm", style: TextStyle(color: Colors.red)), content: const Text("CẢNH BÁO: Bạn đang xóa vĩnh viễn:\n- Toàn bộ tin nhắn.\n- Toàn bộ hình ảnh.\n- Toàn bộ lịch trình và báo thức.\n\nBạn chắc chắn chứ?"), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Giải tán", style: TextStyle(color: Colors.white)))]));

    if (confirm == true) {
      if (mounted) setState(() => isProcessing = true);
      String groupId = widget.groupData['id'];

      try {
        final storageRef = FirebaseStorage.instance.ref().child('group_chat_images/$groupId');
        final listResult = await storageRef.listAll();
        for (var item in listResult.items) {
          await item.delete();
        }
      } catch (e) { debugPrint("Kho ảnh trống hoặc lỗi: $e"); }

      try {
        var tasksSnapshot = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('tasks').get();
        for (var doc in tasksSnapshot.docs) {
          await NotificationService().cancelTask(doc.id.hashCode & 0x7FFFFFFF);
          await doc.reference.delete();
        }

        var msgsSnapshot = await FirebaseFirestore.instance.collection('groups').doc(groupId).collection('messages').get();
        for (var doc in msgsSnapshot.docs) {
          await doc.reference.delete();
        }

        await FirebaseMessaging.instance.unsubscribeFromTopic('group_$groupId');
        await FirebaseFirestore.instance.collection('groups').doc(groupId).delete();

      } catch (e) { debugPrint("Lỗi dọn dẹp Database: $e"); }

      if (mounted) {
        setState(() => isProcessing = false);
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }
  }

  void _inviteFriendsModal() async {
    var myDoc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).get();
    List<dynamic> myFriendIds = myDoc.data()?['friends'] ?? [];

    if (myFriendIds.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bạn chưa có bạn bè trong danh bạ."))); return; }

    List<dynamic> currentMemberIds = widget.groupData['members'] ?? [];
    List<dynamic> eligibleFriendIds = myFriendIds.where((id) => !currentMemberIds.contains(id)).toList();

    if (eligibleFriendIds.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tất cả bạn bè đã ở trong nhóm."))); return; }

    var friendsSnapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: eligibleFriendIds).get();

    showModalBottomSheet(
        context: context,
        builder: (context) {
          bool isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            color: Theme.of(context).scaffoldBackgroundColor, // Đổi màu nền BottomSheet
            child: Column(
              children: [
                Padding(padding: const EdgeInsets.all(16.0), child: Text("Mời bạn bè vào nhóm", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))),
                Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey.shade300),
                Expanded(
                  child: ListView.builder(
                    itemCount: friendsSnapshot.docs.length,
                    itemBuilder: (context, index) {
                      var friend = friendsSnapshot.docs[index].data();
                      String fUid = friendsSnapshot.docs[index].id;
                      String fName = friend['displayName']?.isNotEmpty == true ? friend['displayName'] : (friend['email'] ?? friend['phone']);

                      return ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.pink, child: Icon(Icons.person, color: Colors.white)),
                        title: Text(fName, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                        trailing: ElevatedButton(
                          child: const Text("Mời"),
                          onPressed: () async {
                            Navigator.pop(context);
                            await FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).update({'members': FieldValue.arrayUnion([fUid]), 'roles.$fUid': 'member'});
                            _sendSystemMessage("🎉 ${widget.myName} đã mời $fName vào nhóm.");
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã mời $fName!")));
                          },
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          );
        }
    );
  }

  void _sendFriendRequest(String targetUid) async {
    try {
      await SocialService.sendFriendRequest(widget.currentUserId, widget.myName, targetUid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã gửi lời mời kết bạn!")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi gửi lời mời: $e")));
    }
  }

  void _unfriend(String targetUid, String targetName) async {
    bool? confirm = await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Hủy kết bạn"), content: Text("Bạn chắc chắn muốn hủy kết bạn với $targetName?"), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Thoát")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Hủy kết bạn", style: TextStyle(color: Colors.white)))]));
    if (confirm == true) {
      await SocialService.unfriend(widget.currentUserId, targetUid);
    }
  }

  void _toggleBlockUser(String targetUid, String targetName, bool isBlocked) async {
    try {
      if (isBlocked) {
        await SocialService.toggleBlockUser(widget.currentUserId, targetUid, isBlocked);
        if (mounted) {
          setState(() => myBlockedUsers.remove(targetUid));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã bỏ chặn $targetName")));
        }
      } else {
        bool? confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Chặn người dùng"),
              content: Text("Bạn có chắc muốn chặn $targetName? Bạn sẽ không thấy tin nhắn của người này trong nhóm và không thể nhắn tin riêng."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Chặn")),
              ],
            )
        );
        if (confirm == true) {
          await SocialService.toggleBlockUser(widget.currentUserId, targetUid, isBlocked);
          if (mounted) {
            setState(() {
              myBlockedUsers.add(targetUid);
              myFriends.remove(targetUid);
            });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã chặn $targetName")));
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
    }
  }

  void _showModerationMenu(Map<String, dynamic> targetUser) {
    String targetUid = targetUser['uid'];
    String targetRole = targetUser['role'];
    String targetName = targetUser['displayName']?.isNotEmpty == true ? targetUser['displayName'] : targetUser['phone'];
    bool isMuted = targetUser['isMuted'] == true;
    bool isFriend = myFriends.contains(targetUid);
    bool isBlocked = myBlockedUsers.contains(targetUid);

    bool canKick = false, canMute = false, canPromote = false;
    if (widget.myRole == 'admin') { canKick = true; canMute = true; canPromote = true; }
    else if (widget.myRole == 'co-admin' && targetRole == 'member') { canKick = true; canMute = true; }

    showModalBottomSheet(
        context: context,
        builder: (context) {
          bool isDark = Theme.of(context).brightness == Brightness.dark;
          return SafeArea(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor, // Đổi màu nền BottomSheet
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(padding: const EdgeInsets.all(16.0), child: Text("Thông tin: $targetName", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color))),
                  Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey.shade300),

                  if (targetUid != widget.currentUserId && !isBlocked)
                    ListTile(
                        leading: Icon(isFriend ? Icons.person_remove : Icons.person_add, color: isFriend ? Colors.orange : Colors.blue),
                        title: Text(isFriend ? "Hủy kết bạn" : "Kết bạn", style: TextStyle(color: isFriend ? Colors.orange : Colors.blue)),
                        onTap: () { Navigator.pop(context); isFriend ? _unfriend(targetUid, targetName) : _sendFriendRequest(targetUid); }
                    ),

                  if (targetUid != widget.currentUserId)
                    ListTile(
                        leading: Icon(isBlocked ? Icons.check_circle_outline : Icons.block, color: Colors.red),
                        title: Text(isBlocked ? "Bỏ chặn" : "Chặn người dùng", style: const TextStyle(color: Colors.red)),
                        onTap: () { Navigator.pop(context); _toggleBlockUser(targetUid, targetName, isBlocked); }
                    ),

                  if (canPromote) ListTile(leading: Icon(targetRole == 'member' ? Icons.security : Icons.person, color: isDark ? Colors.white : Colors.black87), title: Text(targetRole == 'member' ? "Thăng cấp Phó nhóm" : "Giáng xuống Thành viên", style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(context); _changeRole(targetUid, targetName, targetRole == 'member' ? 'co-admin' : 'member'); }),
                  if (canMute) ListTile(leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off, color: isMuted ? Colors.green : Colors.orange), title: Text(isMuted ? "Mở khóa Chat" : "Cấm Chat (Mute)", style: TextStyle(color: isMuted ? Colors.green : Colors.orange)), onTap: () { Navigator.pop(context); _toggleMute(targetUid, targetName, isMuted); }),
                  if (canKick) ListTile(leading: const Icon(Icons.person_remove, color: Colors.red), title: const Text("Đuổi khỏi nhóm", style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _kickMember(targetUid, targetName); }),
                ],
              ),
            ),
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    bool canInvite = widget.myRole == 'admin' || widget.myRole == 'co-admin';
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.deepPurple,
          foregroundColor: Colors.white,
          title: const Text("Thông tin Nhóm", style: TextStyle(fontSize: 18)),
          actions: [
            if (widget.myRole == 'admin') IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), tooltip: "Giải tán nhóm", onPressed: _deleteGroup)
            else IconButton(icon: const Icon(Icons.exit_to_app, color: Colors.orange), tooltip: "Rời nhóm", onPressed: _leaveGroup),
          ],
          bottom: TabBar(
            labelColor: isDark ? Colors.amber : Colors.white,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.white54,
            indicatorColor: Colors.amber,
            tabs: const [
              Tab(icon: Icon(Icons.people), text: "Thành viên"),
              Tab(icon: Icon(Icons.image), text: "Kho Ảnh"),
              Tab(icon: Icon(Icons.search), text: "Tìm Chat"),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                // TAB 1: THÀNH VIÊN
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: isDark ? Colors.deepPurple.withOpacity(0.15) : Colors.deepPurple.shade50, // 🔥 Chỉnh nền Dark Mode
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Mã mời tham gia:", style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey)),
                                Text(widget.groupData['inviteCode'] ?? "---", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2, color: isDark ? Colors.deepPurpleAccent : Colors.deepPurple))
                              ]
                          ),
                          Row(
                            children: [
                              if (canInvite) IconButton(icon: Icon(Icons.person_add, color: isDark ? Colors.pinkAccent : Colors.pink), tooltip: "Mời bạn bè", onPressed: _inviteFriendsModal),
                              IconButton(icon: Icon(Icons.copy, color: isDark ? Colors.deepPurpleAccent : Colors.deepPurple), tooltip: "Copy mã", onPressed: () { Clipboard.setData(ClipboardData(text: widget.groupData['inviteCode'])); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã copy mã mời!"))); })
                            ],
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          String role = member['role'];
                          bool isMe = member['uid'] == widget.currentUserId;
                          bool isMuted = member['isMuted'] == true;
                          bool isBlocked = myBlockedUsers.contains(member['uid']);

                          Widget roleIcon = const Icon(Icons.person, color: Colors.white, size: 20);
                          Color avatarColor = Colors.blueGrey;
                          String roleName = "";
                          Color roleColor = isDark ? Colors.grey[400]! : Colors.grey;

                          if (role == 'admin') { roleIcon = const Icon(Icons.star, color: Colors.white, size: 20); avatarColor = Colors.redAccent; roleName = "Quản trị viên"; roleColor = Colors.redAccent; }
                          else if (role == 'co-admin') { roleIcon = const Icon(Icons.shield, color: Colors.white, size: 20); avatarColor = Colors.orange; roleName = "Phó nhóm"; roleColor = Colors.orange; }

                          String name = member['displayName']?.isNotEmpty == true ? member['displayName'] : "Người dùng ẩn danh";
                          String phone = member['phone'] ?? member['email'] ?? "---";

                          return ListTile(
                            leading: Stack(clipBehavior: Clip.none, children: [
                              CircleAvatar(backgroundColor: avatarColor, backgroundImage: member['photoURL'] != null ? NetworkImage(member['photoURL']) : null, child: member['photoURL'] == null ? roleIcon : null),
                              if (isMuted || isBlocked) Positioned(bottom: -2, right: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(isBlocked ? Icons.block : Icons.volume_off, size: 14, color: Colors.red)))
                            ]),
                            // 🔥 Điều chỉnh màu sắc hiển thị tên, sđt khi bị block / mute / dark mode
                            title: Text(name + (isBlocked ? " (Đã chặn)" : ""), style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal, color: (isMuted || isBlocked) ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color)),
                            subtitle: Text(phone, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                            trailing: roleName.isNotEmpty ? Text(roleName, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12)) : null,
                            onTap: isMe ? null : () => _showModerationMenu(member),
                          );
                        },
                      ),
                    )
                  ],
                ),

                // TAB 2: KHO ẢNH
                StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).collection('messages').orderBy('timestamp', descending: true).limit(100).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      var docs = snapshot.data!.docs.where((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        bool hasImage = data['hasImage'] == true || (data['images'] != null && (data['images'] as List).isNotEmpty);
                        return hasImage && data['isRecalled'] != true;
                      }).toList();

                      if (docs.isEmpty) return const Center(child: Text("Chưa có ảnh nào trong nhóm.", style: TextStyle(color: Colors.grey)));

                      List<Map<String, dynamic>> allImages = [];
                      for (var doc in docs) {
                        var msg = doc.data() as Map<String, dynamic>;
                        List<dynamic> images = msg['images'] ?? [];
                        DateTime? time = msg['timestamp'] != null ? (msg['timestamp'] as Timestamp).toDate() : null;
                        String senderName = msg['senderId'] == widget.currentUserId ? "Bạn" : (msg['senderName'] ?? "Ai đó");

                        for (var url in images) {
                          allImages.add({'url': url, 'senderName': senderName, 'time': time});
                        }
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                        itemCount: allImages.length,
                        itemBuilder: (context, index) {
                          var imgInfo = allImages[index];
                          DateTime? time = imgInfo['time'];
                          String timeStr = time != null ? "${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}" : "";

                          return GestureDetector(
                            onTap: () {
                              showDialog(context: context, builder: (_) => Dialog(
                                backgroundColor: Colors.black, insetPadding: EdgeInsets.zero,
                                child: Stack(
                                  children: [
                                    Center(child: InteractiveViewer(child: Image.network(imgInfo['url'], fit: BoxFit.contain))),
                                    Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
                                    Positioned(bottom: 20, left: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Text("Gửi bởi: ${imgInfo['senderName']}\nLúc: $timeStr", style: const TextStyle(color: Colors.white, fontSize: 14)))),
                                  ],
                                ),
                              ));
                            },
                            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imgInfo['url'], fit: BoxFit.cover)),
                          );
                        },
                      );
                    }
                ),

                // TAB 3: TÌM KIẾM TIN NHẮN
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        decoration: InputDecoration(
                            hintText: "Nhập từ khóa...",
                            hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
                            prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[200], // 🔥 Tương thích ô tìm kiếm
                            contentPadding: const EdgeInsets.symmetric(vertical: 0)
                        ),
                        onChanged: (val) => setState(() { searchQuery = val.toLowerCase(); }),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).collection('messages').orderBy('timestamp', descending: true).snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                          var docs = snapshot.data!.docs.where((doc) {
                            if (searchQuery.isEmpty) return false;
                            var data = doc.data() as Map<String, dynamic>;
                            if (data['isRecalled'] == true) return false;
                            String text = (data['text'] ?? "").toString().toLowerCase();
                            return text.contains(searchQuery);
                          }).toList();

                          if (searchQuery.isNotEmpty && docs.isEmpty) return Center(child: Text("Không tìm thấy tin nhắn nào.", style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)));
                          if (searchQuery.isEmpty) return const Center(child: Text("Nhập từ khóa để tìm kiếm", style: TextStyle(color: Colors.grey)));

                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              var msg = docs[index].data() as Map<String, dynamic>;
                              bool isMyMsg = msg['senderId'] == widget.currentUserId;
                              DateTime? time = msg['timestamp'] != null ? (msg['timestamp'] as Timestamp).toDate() : null;
                              String timeStr = time != null ? "${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}" : "";

                              return ListTile(
                                leading: Icon(isMyMsg ? Icons.arrow_circle_right : Icons.arrow_circle_left, color: isMyMsg ? (isDark ? Colors.deepPurpleAccent : Colors.deepPurple) : Colors.grey),
                                title: Text(msg['text'], style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                subtitle: Text("${isMyMsg ? 'Bạn' : msg['senderName']} • $timeStr", style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isProcessing)
              Container(
                  color: Colors.black54,
                  child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text("Đang dọn dẹp dữ liệu...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                        ],
                      )
                  )
              ),
          ],
        ),
      ),
    );
  }
}