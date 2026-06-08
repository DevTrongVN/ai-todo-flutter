import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import 'private_chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final String myUid = FirebaseAuth.instance.currentUser!.uid;

  // 🔥 Biến lưu trữ tìm kiếm trong danh bạ
  String _contactSearchQuery = "";
  final TextEditingController _contactSearchController = TextEditingController();

  String get myName {
    User? u = FirebaseAuth.instance.currentUser;
    return (u?.displayName != null && u!.displayName!.isNotEmpty) ? u.displayName! : (u?.phoneNumber ?? u?.email ?? "Ẩn danh");
  }

  // UI TAB 1: TÌM KIẾM BẠN BÈ MỚI TRÊN HỆ THỐNG
  Widget _buildSearchTab() {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    return StatefulBuilder(
        builder: (context, setSearchState) {
          void searchUser() async {
            String input = searchController.text.trim();
            if (input.isEmpty) return;

            setSearchState(() => isSearching = true);
            String phoneInput = input.startsWith('0') ? '+84${input.substring(1)}' : input;

            try {
              var emailQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: input).get();
              var phoneQuery = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: phoneInput).get();

              Map<String, Map<String, dynamic>> resultsMap = {};
              for (var doc in emailQuery.docs) {
                if (doc.id != myUid) resultsMap[doc.id] = {...doc.data(), "uid": doc.id};
              }
              for (var doc in phoneQuery.docs) {
                if (doc.id != myUid) resultsMap[doc.id] = {...doc.data(), "uid": doc.id};
              }

              setSearchState(() => searchResults = resultsMap.values.toList());

              if (searchResults.isEmpty && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Không tìm thấy ai.")));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi tìm kiếm: $e")));
            }
            setSearchState(() => isSearching = false);
          }

          void sendFriendRequest(String targetUid) async {
            try {
              await FirebaseFirestore.instance.collection('users').doc(targetUid).set({
                'friendRequests': FieldValue.arrayUnion([myUid])
              }, SetOptions(merge: true));

              await NotificationService().sendFriendRequestNotification(targetUid, myName);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã gửi lời mời!")));
                setSearchState(() => searchResults.removeWhere((u) => u['uid'] == targetUid));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi gửi lời mời: $e")));
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                            hintText: "Nhập Email hoặc Số ĐT...",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0)
                        ),
                        onSubmitted: (_) => searchUser(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: searchUser,
                      child: const Text("Tìm"),
                    )
                  ],
                ),
                const SizedBox(height: 20),
                if (isSearching) const CircularProgressIndicator(),
                Expanded(
                  child: ListView.separated(
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = searchResults[index];
                      return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox();
                            var data = snapshot.data!.data() as Map<String, dynamic>?;
                            List friends = data?['friends'] ?? [];
                            List blocked = data?['blockedUsers'] ?? [];

                            bool isFriend = friends.contains(user['uid']);
                            bool isBlocked = blocked.contains(user['uid']);

                            if (isBlocked) return const SizedBox.shrink();

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.pink,
                                backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                                child: user['photoURL'] == null ? const Icon(Icons.person, color: Colors.white) : null,
                              ),
                              title: Text(user['displayName'] ?? "Ẩn danh", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(user['email']?.isNotEmpty == true ? user['email'] : user['phone']),
                              trailing: isFriend
                                  ? const Text("Đã là bạn", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                  : ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                onPressed: () => sendFriendRequest(user['uid']),
                                child: const Text("Kết bạn"),
                              ),
                            );
                          }
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

  // UI TAB 2: LỜI MỜI
  Widget _buildRequestsTab() {
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          Map<String, dynamic>? data = snapshot.data!.data() as Map<String, dynamic>?;
          List<dynamic> requestIds = data?['friendRequests'] ?? [];

          if (requestIds.isEmpty) return const Center(child: Text("Không có lời mời nào."));

          return FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: requestIds).get(),
              builder: (context, reqSnapshot) {
                if (!reqSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                var reqUsers = reqSnapshot.data!.docs;

                void acceptRequest(String targetUid) async {
                  final db = FirebaseFirestore.instance;
                  await db.collection('users').doc(myUid).update({'friends': FieldValue.arrayUnion([targetUid])});
                  await db.collection('users').doc(targetUid).update({'friends': FieldValue.arrayUnion([myUid])});
                  await db.collection('users').doc(myUid).update({'friendRequests': FieldValue.arrayRemove([targetUid])});
                }

                void rejectRequest(String targetUid) async {
                  await FirebaseFirestore.instance.collection('users').doc(myUid).update({'friendRequests': FieldValue.arrayRemove([targetUid])});
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reqUsers.length,
                  itemBuilder: (context, index) {
                    var user = reqUsers[index].data() as Map<String, dynamic>;
                    String uid = reqUsers[index].id;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                          child: user['photoURL'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(user['displayName'] ?? "Ẩn danh"),
                        subtitle: const Text("Muốn kết bạn với bạn"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.check_circle, color: Colors.green, size: 30), onPressed: () => acceptRequest(uid)),
                            IconButton(icon: const Icon(Icons.cancel, color: Colors.red, size: 30), onPressed: () => rejectRequest(uid)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }
          );
        }
    );
  }

  // UI TAB 3: DANH BẠ (KÈM TÌM KIẾM)
  Widget _buildFriendsListTab() {
    return Column(
      children: [
        // 🔥 THANH TÌM KIẾM TRONG DANH BẠ
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _contactSearchController,
            decoration: InputDecoration(
              hintText: "Tìm bạn bè trong danh bạ...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (value) {
              setState(() {
                _contactSearchQuery = value;
              });
            },
          ),
        ),

        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                Map<String, dynamic>? data = snapshot.data!.data() as Map<String, dynamic>?;
                List<dynamic> friendIds = data?['friends'] ?? [];
                List<dynamic> blockedIds = data?['blockedUsers'] ?? [];

                if (friendIds.isEmpty && blockedIds.isEmpty) return const Center(child: Text("Bạn chưa có người bạn nào."));

                List<dynamic> allRelevantIds = {...friendIds, ...blockedIds}.toList();

                return FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: allRelevantIds).get(),
                    builder: (context, friendsSnapshot) {
                      if (!friendsSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var users = friendsSnapshot.data!.docs;

                      // 🔥 LỌC DANH SÁCH THEO TỪ KHÓA TÌM KIẾM
                      var filteredUsers = users.where((doc) {
                        var user = doc.data() as Map<String, dynamic>;
                        String name = user['displayName']?.toLowerCase() ?? "ẩn danh";
                        String email = user['email']?.toLowerCase() ?? "";
                        String phone = user['phone']?.toLowerCase() ?? "";
                        String query = _contactSearchQuery.toLowerCase();

                        return name.contains(query) || email.contains(query) || phone.contains(query);
                      }).toList();

                      void removeFriend(String targetUid, String targetName) async {
                        bool? confirm = await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                                title: const Text("Hủy kết bạn"),
                                content: Text("Bạn chắc chắn muốn hủy kết bạn với $targetName?"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Thoát")),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Hủy kết bạn", style: TextStyle(color: Colors.white)))
                                ]
                            )
                        );

                        if (confirm == true) {
                          final db = FirebaseFirestore.instance;
                          await db.collection('users').doc(myUid).update({'friends': FieldValue.arrayRemove([targetUid])});
                          await db.collection('users').doc(targetUid).update({'friends': FieldValue.arrayRemove([myUid])});
                        }
                      }

                      void toggleBlock(String targetUid, String targetName, bool isBlocked) async {
                        bool? confirm = await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                                title: Text(isBlocked ? "Bỏ chặn" : "Chặn người dùng"),
                                content: Text(isBlocked ? "Bạn muốn bỏ chặn $targetName?" : "Bạn có chắc muốn chặn $targetName? Hai người sẽ không thể nhắn tin riêng."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: isBlocked ? Colors.green : Colors.red), onPressed: () => Navigator.pop(context, true), child: Text(isBlocked ? "Xác nhận" : "Chặn", style: const TextStyle(color: Colors.white)))
                                ]
                            )
                        );

                        if (confirm == true) {
                          final db = FirebaseFirestore.instance;
                          if (isBlocked) {
                            await db.collection('users').doc(myUid).update({'blockedUsers': FieldValue.arrayRemove([targetUid])});
                          } else {
                            await db.collection('users').doc(myUid).update({'blockedUsers': FieldValue.arrayUnion([targetUid])});
                            await db.collection('users').doc(myUid).update({'friends': FieldValue.arrayRemove([targetUid])});
                            await db.collection('users').doc(targetUid).update({'friends': FieldValue.arrayRemove([myUid])});
                          }
                        }
                      }

                      if (filteredUsers.isEmpty) {
                        return const Center(child: Text("Không tìm thấy bạn bè nào."));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          var user = filteredUsers[index].data() as Map<String, dynamic>;
                          String uid = filteredUsers[index].id;
                          String name = user['displayName'] ?? "Ẩn danh";
                          bool isBlocked = blockedIds.contains(uid);
                          bool isFriend = friendIds.contains(uid);

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isBlocked ? Colors.grey : Colors.green,
                                backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                                child: user['photoURL'] == null ? const Icon(Icons.person, color: Colors.white) : null,
                              ),
                              // 🔥 ĐÃ FIX LỖI MÀU CHỮ: Xóa "color: Colors.black", thay bằng null để tự đổi màu Sáng/Tối
                              title: Text(
                                  name + (isBlocked ? " (Đã chặn)" : ""),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isBlocked ? Colors.grey : null
                                  )
                              ),
                              subtitle: Text(user['email']?.isNotEmpty == true ? user['email'] : user['phone']),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isBlocked && isFriend)
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble, color: Colors.blue),
                                      tooltip: "Nhắn tin",
                                      onPressed: () {
                                        String chatId = myUid.compareTo(uid) < 0 ? '${myUid}_$uid' : '${uid}_$myUid';
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateChatScreen(
                                          chatId: chatId,
                                          targetUid: uid,
                                          targetName: name,
                                          targetAvatar: user['photoURL'],
                                        )));
                                      },
                                    ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'remove') removeFriend(uid, name);
                                      else if (value == 'block') toggleBlock(uid, name, isBlocked);
                                    },
                                    itemBuilder: (context) => [
                                      if (isFriend)
                                        const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.person_remove, color: Colors.orange, size: 20), SizedBox(width: 8), Text("Hủy kết bạn")])),
                                      PopupMenuItem(value: 'block', child: Row(children: [Icon(isBlocked ? Icons.check_circle : Icons.block, color: Colors.red, size: 20), SizedBox(width: 8), Text(isBlocked ? "Bỏ chặn" : "Chặn người dùng")])),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }
                );
              }
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Bạn bè & Danh bạ"),
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.contacts), text: "Danh bạ"),
              Tab(icon: Icon(Icons.person_add), text: "Lời mời"),
              Tab(icon: Icon(Icons.search), text: "Tìm kiếm"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFriendsListTab(),
            _buildRequestsTab(),
            _buildSearchTab(),
          ],
        ),
      ),
    );
  }
}