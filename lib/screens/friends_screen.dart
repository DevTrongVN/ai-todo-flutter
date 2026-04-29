import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> myFriends = [];
  bool isLoading = false;

  final String myUid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  // 1. LẮNG NGHE DANH SÁCH BẠN BÈ THEO THỜI GIAN THỰC
  void _loadFriends() {
    FirebaseFirestore.instance.collection('users').doc(myUid).snapshots().listen((doc) async {
      if (doc.exists && doc.data()!.containsKey('friends')) {
        List<dynamic> friendIds = doc['friends'];
        if (friendIds.isEmpty) {
          if (mounted) setState(() => myFriends = []);
          return;
        }

        // Lấy thông tin chi tiết của những người bạn từ mảng ID
        var friendsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: friendIds)
            .get();

        if (mounted) {
          setState(() {
            myFriends = friendsSnapshot.docs.map((d) => {...d.data(), "uid": d.id}).toList();
          });
        }
      }
    });
  }

  // 2. TÌM KIẾM ĐỒNG THỜI QUA EMAIL VÀ SĐT
  void searchUser() async {
    String input = searchController.text.trim();
    if (input.isEmpty) return;

    setState(() => isLoading = true);

    // Chuẩn hóa SĐT: Đổi 09... thành +849... để khớp với Firebase
    String phoneInput = input;
    if (phoneInput.startsWith('0')) phoneInput = '+84${phoneInput.substring(1)}';

    try {
      // Bắn 2 truy vấn cùng lúc
      var emailQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: input).get();
      var phoneQuery = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: phoneInput).get();

      // Gộp kết quả, chống trùng lặp và loại bỏ chính mình
      Map<String, Map<String, dynamic>> resultsMap = {};

      for (var doc in emailQuery.docs) {
        if (doc.id != myUid) resultsMap[doc.id] = {...doc.data(), "uid": doc.id};
      }
      for (var doc in phoneQuery.docs) {
        if (doc.id != myUid) resultsMap[doc.id] = {...doc.data(), "uid": doc.id};
      }

      setState(() {
        searchResults = resultsMap.values.toList();
      });

      if (searchResults.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Không tìm thấy người dùng nào.")));
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi tìm kiếm: $e")));
    }
    setState(() => isLoading = false);
  }

  // 3. XỬ LÝ KẾT BẠN (LƯU VÀO CLOUD)
  void addFriend(String targetUid) async {
    try {
      final db = FirebaseFirestore.instance;
      // Thêm họ vào mảng friends của mình
      await db.collection('users').doc(myUid).set({
        'friends': FieldValue.arrayUnion([targetUid])
      }, SetOptions(merge: true));

      // Thêm mình vào mảng friends của họ (Kết bạn 2 chiều)
      await db.collection('users').doc(targetUid).set({
        'friends': FieldValue.arrayUnion([myUid])
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã kết bạn thành công!")));
        setState(() {
          searchResults.clear();
          searchController.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi kết bạn: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bạn bè & Danh bạ"),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ô TÌM KIẾM
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                        hintText: "Nhập chính xác Email hoặc Số ĐT...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0)
                    ),
                    onSubmitted: (_) => searchUser(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)
                  ),
                  onPressed: searchUser,
                  child: const Text("Tìm"),
                )
              ],
            ),
            const SizedBox(height: 10),

            if (isLoading) const Center(child: CircularProgressIndicator()),

            // KẾT QUẢ TÌM KIẾM
            if (searchResults.isNotEmpty) ...[
              const Text("Kết quả tìm kiếm:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = searchResults[index];
                    String name = user['displayName']?.isNotEmpty == true ? user['displayName'] : "Người dùng ẩn danh";
                    String info = user['email']?.isNotEmpty == true ? user['email'] : user['phone'];

                    // Kiểm tra xem đã là bạn bè chưa
                    bool isAlreadyFriend = myFriends.any((f) => f['uid'] == user['uid']);

                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.pink, child: Icon(Icons.person, color: Colors.white)),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(info),
                      trailing: isAlreadyFriend
                          ? const Text("Đã là bạn", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                          : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        onPressed: () => addFriend(user['uid']),
                        child: const Text("Kết bạn"),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Divider(),
            const SizedBox(height: 10),

            // DANH SÁCH BẠN BÈ
            const Text("Danh bạ của bạn", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
                child: myFriends.isEmpty
                    ? const Center(child: Text("Bạn chưa có người bạn nào.\nHãy tìm kiếm và kết bạn ngay nhé!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                  itemCount: myFriends.length,
                  itemBuilder: (context, index) {
                    final friend = myFriends[index];
                    String name = friend['displayName']?.isNotEmpty == true ? friend['displayName'] : "Người dùng ẩn danh";
                    String info = friend['email']?.isNotEmpty == true ? friend['email'] : friend['phone'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.person, color: Colors.white)),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(info),
                        trailing: IconButton(
                          icon: const Icon(Icons.chat_bubble, color: Colors.blue),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tính năng Chat sẽ ra mắt ở phần sau!")));
                          },
                        ),
                      ),
                    );
                  },
                )
            )
          ],
        ),
      ),
    );
  }
}