import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

  // HÀM TẠO MÃ NGẪU NHIÊN 6 KÝ TỰ
  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // TẠO NHÓM MỚI
  void _createGroup() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tạo nhóm mới"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "Nhập tên nhóm..."),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(context);

              String code = "G-${_generateCode()}"; // VD: G-A1B2C3
              var ref = FirebaseFirestore.instance.collection('groups').doc();

              await ref.set({
                'id': ref.id,
                'name': nameController.text.trim(),
                'inviteCode': code,
                'members': [myUid],
                'roles': {myUid: 'admin'}, // Người tạo tự động làm admin
                'createdAt': DateTime.now().toIso8601String()
              });

              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tạo nhóm thành công!")));
            },
            child: const Text("Tạo"),
          )
        ],
      ),
    );
  }

  // VÀO NHÓM BẰNG MÃ
  void _joinGroup() {
    TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tham gia nhóm"),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(hintText: "Nhập mã nhóm (VD: G-123456)"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              String code = codeController.text.trim().toUpperCase();
              if (code.isEmpty) return;
              Navigator.pop(context);

              // Tìm nhóm có mã code tương ứng
              var query = await FirebaseFirestore.instance.collection('groups').where('inviteCode', isEqualTo: code).get();

              if (query.docs.isEmpty) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mã nhóm không tồn tại!")));
                return;
              }

              var doc = query.docs.first;

              // Cập nhật Database: Thêm mình vào mảng members, set role là member
              await doc.reference.update({
                'members': FieldValue.arrayUnion([myUid]),
                'roles.$myUid': 'member'
              });

              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tham gia thành công!")));
            },
            child: const Text("Vào nhóm"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (myUid.isEmpty) {
      return const Scaffold(body: Center(child: Text("Vui lòng đăng nhập để sử dụng tính năng Nhóm")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nhóm của tôi"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.add_box), onPressed: _createGroup, tooltip: "Tạo nhóm"),
          IconButton(icon: const Icon(Icons.login), onPressed: _joinGroup, tooltip: "Tham gia nhóm"),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Lắng nghe realtime các nhóm mà mình là thành viên
        stream: FirebaseFirestore.instance.collection('groups').where('members', arrayContains: myUid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_off, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  const Text("Bạn chưa tham gia nhóm nào", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text("Tạo nhóm"), onPressed: _createGroup),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(icon: const Icon(Icons.login), label: const Text("Vào nhóm"), onPressed: _joinGroup),
                    ],
                  )
                ],
              ),
            );
          }

          var groups = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              var group = groups[index].data() as Map<String, dynamic>;
              int memberCount = (group['members'] as List).length;
              bool isAdmin = group['roles'][myUid] == 'admin';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: Icon(Icons.groups, color: Colors.white),
                  ),
                  title: Text(group['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text("$memberCount thành viên  •  Mã: ${group['inviteCode']}"),
                  trailing: isAdmin ? const Icon(Icons.star, color: Colors.amber) : null,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupData: group, currentUserId: myUid)));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}