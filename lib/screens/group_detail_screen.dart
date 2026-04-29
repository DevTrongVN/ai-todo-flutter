import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_group_task_screen.dart'; // 👉 IMPORT MÀN HÌNH MỚI TẠO

class GroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> groupData;
  final String currentUserId;

  const GroupDetailScreen({super.key, required this.groupData, required this.currentUserId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  Map<String, dynamic> currentGroupData = {};
  List<Map<String, dynamic>> members = [];
  bool isLoading = true;

  final TextEditingController _chatController = TextEditingController();

  String get myName {
    User? u = FirebaseAuth.instance.currentUser;
    if (u == null) return "Ẩn danh";
    return (u.displayName != null && u.displayName!.isNotEmpty) ? u.displayName! : (u.phoneNumber ?? u.email ?? "Ẩn danh");
  }

  @override
  void initState() {
    super.initState();
    currentGroupData = widget.groupData;
    _loadMembers();
  }

  void _loadMembers() {
    FirebaseFirestore.instance.collection('groups').doc(widget.groupData['id']).snapshots().listen((groupDoc) async {
      if (!groupDoc.exists) {
        if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nhóm đã bị giải tán!"))); }
        return;
      }

      currentGroupData = groupDoc.data() as Map<String, dynamic>;
      List<dynamic> memberIds = currentGroupData['members'] ?? [];
      Map<String, dynamic> roles = currentGroupData['roles'] ?? {};
      List<dynamic> mutedList = currentGroupData['muted'] ?? [];

      if (!memberIds.contains(widget.currentUserId)) {
        if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bạn đã rời hoặc bị mời khỏi nhóm!"))); }
        return;
      }

      if (memberIds.isEmpty) return;

      var usersSnapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: memberIds).get();

      if (mounted) {
        setState(() {
          members = usersSnapshot.docs.map((doc) => { ...doc.data(), "uid": doc.id, "role": roles[doc.id] ?? 'member', "isMuted": mutedList.contains(doc.id) }).toList();
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

  // 🔥 HÀM GỬI TIN NHẮN HỆ THỐNG
  void _sendSystemMessage(String content) {
    FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('messages').add({
      'text': content,
      'isSystem': true, // Cờ nhận biết tin nhắn hệ thống
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ================= MODERATION & INVITE =================
  void _kickMember(String targetUid, String targetName) async {
    await FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).update({
      'members': FieldValue.arrayRemove([targetUid]),
      'roles.$targetUid': FieldValue.delete(),
    });
    _sendSystemMessage("👢 Quản trị viên đã mời $targetName ra khỏi nhóm.");
  }

  void _leaveGroup() async {
    bool? confirm = await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Rời nhóm"), content: const Text("Bạn có chắc muốn rời nhóm?"), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), onPressed: () => Navigator.pop(context, true), child: const Text("Rời đi", style: TextStyle(color: Colors.white)))]));
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).update({
        'members': FieldValue.arrayRemove([widget.currentUserId]),
        'roles.${widget.currentUserId}': FieldValue.delete(),
      });
      _sendSystemMessage("👋 $myName đã rời khỏi nhóm.");
    }
  }

  // 🔥 TÍNH NĂNG MỜI BẠN BÈ VÀO NHÓM
  void _inviteFriendsModal() async {
    // 1. Lấy danh sách bạn bè của mình
    var myDoc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).get();
    List<dynamic> myFriendIds = myDoc.data()?['friends'] ?? [];

    if (myFriendIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bạn chưa có người bạn nào trong danh bạ.")));
      return;
    }

    // 2. Lọc ra những người chưa có trong nhóm
    List<dynamic> currentMemberIds = currentGroupData['members'] ?? [];
    List<dynamic> eligibleFriendIds = myFriendIds.where((id) => !currentMemberIds.contains(id)).toList();

    if (eligibleFriendIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tất cả bạn bè của bạn đều đã ở trong nhóm này.")));
      return;
    }

    var friendsSnapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: eligibleFriendIds).get();

    showModalBottomSheet(
        context: context,
        builder: (context) {
          return Column(
            children: [
              const Padding(padding: EdgeInsets.all(16.0), child: Text("Mời bạn bè vào nhóm", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: friendsSnapshot.docs.length,
                  itemBuilder: (context, index) {
                    var friend = friendsSnapshot.docs[index].data();
                    String fUid = friendsSnapshot.docs[index].id;
                    String fName = friend['displayName']?.isNotEmpty == true ? friend['displayName'] : (friend['email'] ?? friend['phone']);

                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.pink, child: Icon(Icons.person, color: Colors.white)),
                      title: Text(fName),
                      trailing: ElevatedButton(
                        child: const Text("Mời"),
                        onPressed: () async {
                          Navigator.pop(context);
                          // Thêm vào nhóm
                          await FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).update({
                            'members': FieldValue.arrayUnion([fUid]),
                            'roles.$fUid': 'member'
                          });
                          // Bắn tin nhắn hệ thống
                          _sendSystemMessage("🎉 $myName đã mời $fName vào nhóm.");
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Đã mời $fName!")));
                        },
                      ),
                    );
                  },
                ),
              )
            ],
          );
        }
    );
  }

  // ================= CÁC HÀM CÒN LẠI GIỮ NGUYÊN HOẶC CHỈNH NHẸ =================
  void _toggleMute(String targetUid, String targetName, bool isMuted) async {
    await FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).update({'muted': isMuted ? FieldValue.arrayRemove([targetUid]) : FieldValue.arrayUnion([targetUid])});
  }
  void _changeRole(String targetUid, String targetName, String newRole) async {
    await FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).update({'roles.$targetUid': newRole});
  }
  void _deleteGroup() async {
    bool? confirm = await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Giải tán nhóm", style: TextStyle(color: Colors.red)), content: const Text("Xóa vĩnh viễn nhóm?"), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Giải tán", style: TextStyle(color: Colors.white)))]));
    if (confirm == true) await FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).delete();
  }

  void _showModerationMenu(Map<String, dynamic> targetUser, String myRole) {
    String targetUid = targetUser['uid'];
    String targetRole = targetUser['role'];
    String targetName = targetUser['displayName']?.isNotEmpty == true ? targetUser['displayName'] : targetUser['phone'];
    bool isMuted = targetUser['isMuted'] == true;

    bool canKick = false, canMute = false, canPromote = false;
    if (myRole == 'admin') { canKick = true; canMute = true; canPromote = true; }
    else if (myRole == 'co-admin' && targetRole == 'member') { canKick = true; canMute = true; }

    if (!canKick && !canMute && !canPromote) return;

    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.all(16.0), child: Text("Quản lý: $targetName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                const Divider(height: 1),
                if (canPromote) ListTile(leading: Icon(targetRole == 'member' ? Icons.security : Icons.person), title: Text(targetRole == 'member' ? "Thăng cấp Phó nhóm" : "Giáng xuống Thành viên"), onTap: () { Navigator.pop(context); _changeRole(targetUid, targetName, targetRole == 'member' ? 'co-admin' : 'member'); }),
                if (canMute) ListTile(leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off, color: isMuted ? Colors.green : Colors.orange), title: Text(isMuted ? "Mở khóa Chat" : "Cấm Chat (Mute)", style: TextStyle(color: isMuted ? Colors.green : Colors.orange)), onTap: () { Navigator.pop(context); _toggleMute(targetUid, targetName, isMuted); }),
                if (canKick) ListTile(leading: const Icon(Icons.person_remove, color: Colors.red), title: const Text("Đuổi khỏi nhóm", style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _kickMember(targetUid, targetName); }),
              ],
            ),
          );
        }
    );
  }

  // ================= CHAT =================
  void _sendChatMessage() {
    String text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('messages').add({
      'text': text, 'senderId': widget.currentUserId, 'senderName': myName, 'isSystem': false, 'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Widget _buildChatTab(bool isMeMuted) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('messages').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data!.docs;
              if (docs.isEmpty) return const Center(child: Text("Hãy gửi tin nhắn đầu tiên!", style: TextStyle(color: Colors.grey)));

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var msg = docs[index].data() as Map<String, dynamic>;

                  // 🔥 NẾU LÀ TIN NHẮN HỆ THỐNG
                  if (msg['isSystem'] == true) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(12)),
                          child: Text(msg['text'], style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }

                  // TIN NHẮN BÌNH THƯỜNG
                  bool isMyMsg = msg['senderId'] == widget.currentUserId;
                  return Align(
                    alignment: isMyMsg ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      child: Column(
                        crossAxisAlignment: isMyMsg ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (!isMyMsg) Text(msg['senderName'] ?? "Ẩn danh", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                                color: isMyMsg ? Colors.deepPurple : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMyMsg ? const Radius.circular(0) : const Radius.circular(16),
                                  bottomLeft: !isMyMsg ? const Radius.circular(0) : const Radius.circular(16),
                                )
                            ),
                            child: Text(msg['text'], style: TextStyle(color: isMyMsg ? Colors.white : Colors.black87, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300))),
          child: isMeMuted
              ? const Padding(padding: EdgeInsets.all(12.0), child: Text("🚫 Bạn đã bị Quản trị viên cấm chat.", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center))
              : Row(
            children: [
              Expanded(child: TextField(controller: _chatController, decoration: InputDecoration(hintText: "Nhập tin nhắn...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey[200], contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), onSubmitted: (_) => _sendChatMessage())),
              const SizedBox(width: 8),
              CircleAvatar(backgroundColor: Colors.deepPurple, child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: _sendChatMessage))
            ],
          ),
        )
      ],
    );
  }

  // ================= LỊCH NHÓM =================
  Widget _buildTasksTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        onPressed: () {
          // 👉 MỞ MÀN HÌNH TẠO LỊCH NHÓM MỚI
          Navigator.push(context, MaterialPageRoute(builder: (_) => AddGroupTaskScreen(groupId: currentGroupData['id'], creatorName: myName)));
        },
        child: const Icon(Icons.add_task),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('tasks').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Nhóm chưa có lịch trình nào.", style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var task = docs[index].data() as Map<String, dynamic>;
              String docId = docs[index].id;
              bool isDone = task['isCompleted'] == true;

              DateTime time = DateTime.parse(task['datetime']);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: Checkbox(value: isDone, activeColor: Colors.deepPurple, onChanged: (val) { FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('tasks').doc(docId).update({'isCompleted': val}); }),
                  title: Text(task['title'] ?? "", style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null, fontWeight: FontWeight.bold)),
                  subtitle: Text("Tạo bởi: ${task['createdBy']} • ${time.hour}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}\nLặp: ${task['repeatMode']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => FirebaseFirestore.instance.collection('groups').doc(currentGroupData['id']).collection('tasks').doc(docId).delete()),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ================= THÀNH VIÊN =================
  Widget _buildMembersTab(String myRole) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.deepPurple.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Mã mời tham gia:", style: TextStyle(color: Colors.grey)),
                  Text(currentGroupData['inviteCode'] ?? "---", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.deepPurple)),
                ],
              ),
              Row(
                children: [
                  // NÚT MỜI BẠN BÈ (Chỉ Admin/Co-admin mới thấy)
                  if (myRole == 'admin' || myRole == 'co-admin')
                    IconButton(icon: const Icon(Icons.person_add, color: Colors.pink), tooltip: "Mời bạn bè", onPressed: _inviteFriendsModal),
                  IconButton(icon: const Icon(Icons.copy, color: Colors.deepPurple), tooltip: "Copy mã", onPressed: () { Clipboard.setData(ClipboardData(text: currentGroupData['inviteCode'])); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã copy mã mời!"))); })
                ],
              )
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              String role = member['role'];
              bool isMe = member['uid'] == widget.currentUserId;
              bool isMuted = member['isMuted'] == true;

              Widget roleIcon = const Icon(Icons.person, color: Colors.white, size: 20);
              Color avatarColor = Colors.blueGrey;
              String roleName = "";
              Color roleColor = Colors.grey;

              if (role == 'admin') { roleIcon = const Icon(Icons.star, color: Colors.white, size: 20); avatarColor = Colors.redAccent; roleName = "Quản trị viên"; roleColor = Colors.redAccent; }
              else if (role == 'co-admin') { roleIcon = const Icon(Icons.shield, color: Colors.white, size: 20); avatarColor = Colors.orange; roleName = "Phó nhóm"; roleColor = Colors.orange; }

              bool canTap = false;
              if (!isMe) {
                if (myRole == 'admin') canTap = true;
                if (myRole == 'co-admin' && role == 'member') canTap = true;
              }

              return ListTile(
                leading: Stack(clipBehavior: Clip.none, children: [CircleAvatar(backgroundColor: avatarColor, child: roleIcon), if (isMuted) Positioned(bottom: -2, right: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.volume_off, size: 14, color: Colors.red)))]),
                title: Text(member['displayName']?.isNotEmpty == true ? member['displayName'] : "Người dùng ${member['phone']}", style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal, color: isMuted ? Colors.grey : Colors.black)),
                subtitle: Text(member['email']?.isNotEmpty == true ? member['email'] : member['phone']),
                trailing: roleName.isNotEmpty ? Text(roleName, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12)) : null,
                onTap: canTap ? () => _showModerationMenu(member, myRole) : null,
              );
            },
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String myRole = currentGroupData['roles']?[widget.currentUserId] ?? 'member';
    List<dynamic> mutedList = currentGroupData['muted'] ?? [];
    bool isMeMuted = mutedList.contains(widget.currentUserId);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(currentGroupData['name'] ?? "Đang tải..."),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          actions: [
            if (myRole == 'admin') IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), tooltip: "Giải tán nhóm", onPressed: _deleteGroup)
            else IconButton(icon: const Icon(Icons.exit_to_app, color: Colors.orange), tooltip: "Rời nhóm", onPressed: _leaveGroup),
          ],
          bottom: const TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: Colors.amber, tabs: [Tab(icon: Icon(Icons.chat), text: "Thảo luận"), Tab(icon: Icon(Icons.event_note), text: "Lịch nhóm"), Tab(icon: Icon(Icons.people), text: "Thành viên")]),
        ),
        body: TabBarView(children: [_buildChatTab(isMeMuted), _buildTasksTab(), _buildMembersTab(myRole)]),
      ),
    );
  }
}