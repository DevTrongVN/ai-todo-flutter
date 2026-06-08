import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../main.dart';
import '../services/social_service.dart';
import '../services/notification_service.dart';
import '../database/db_helper.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool isLoading = false;
  String loadingText = "Đang tải..."; // Trạng thái hiển thị khi Deep Delete

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 🔥 CHIẾN DỊCH DEEP DELETE
  Future<void> _performDelete() async {
    setState(() {
      isLoading = true;
      loadingText = "Đang khởi tạo quá trình xóa dữ liệu...";
    });

    try {
      String uid = user!.uid;
      String myName = user!.displayName ?? "Người dùng";

      // 1. Lấy thông tin Document của User
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      List<dynamic> friends = userDoc.data()?['friends'] ?? [];

      // 2. Xóa sạch Lịch trình cá nhân (Local DB & Notifications)
      setState(() => loadingText = "Đang dọn dẹp lịch trình cá nhân...");
      final dbHelper = DBHelper();
      var allTasks = await dbHelper.getAllTasks();
      for (var t in allTasks) {
        await dbHelper.deleteTask(t['id']);
      }

      // 3. Hủy kết bạn toàn bộ danh bạ
      setState(() => loadingText = "Đang hủy kết nối bạn bè...");
      await SocialService.unfriendAll(uid, friends);

      // 4. Xử lý dữ liệu Nhóm (Rời / Giải tán)
      setState(() => loadingText = "Đang xử lý dữ liệu nhóm...");
      await SocialService.processGroupsOnDelete(uid, myName);

      // 5. Quét và xóa tin nhắn Private Chat
      setState(() => loadingText = "Đang xóa dữ liệu tin nhắn riêng tư...");
      await SocialService.deleteAllPrivateChats(uid);

      // 6. Xóa Avatar trên Firebase Storage
      setState(() => loadingText = "Đang dọn dẹp bộ nhớ Storage...");
      try {
        await FirebaseStorage.instance.ref().child('avatars/$uid.jpg').delete();
      } catch (e) {
        debugPrint("Không có avatar để xóa.");
      }

      // 7. Xóa sạch thông báo Local, Push Token và Cache
      setState(() => loadingText = "Đang ngắt kết nối hệ thống...");
      await NotificationService().clearAllNotificationsOnLogout();

      // 8. Đòn ân huệ: Xóa User Document và Firebase Auth
      setState(() => loadingText = "Đang xóa tài khoản vĩnh viễn...");
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      await GoogleSignIn().signOut();
      await user!.delete();

      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (e) {
      _showMsg("Lỗi khi xóa tài khoản: Vui lòng thử lại sau.");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _verifyPhoneForReauth(String phoneNumber) async {
    setState(() {
      isLoading = true;
      loadingText = "Đang gửi mã xác thực SMS...";
    });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await user!.reauthenticateWithCredential(credential);
        await _performDelete();
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => isLoading = false);
        _showMsg("Lỗi xác thực SMS: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() => isLoading = false);
        _showOTPDialog(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  void _showOTPDialog(String verificationId) {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Xác thực OTP"),
        content: TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 5),
          maxLength: 6,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              try {
                PhoneAuthCredential credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: otpController.text.trim());
                await user!.reauthenticateWithCredential(credential);
                Navigator.pop(context);
                await _performDelete();
              } catch (e) {
                _showMsg("Mã OTP không hợp lệ!");
              }
            },
            child: const Text("Xác nhận"),
          )
        ],
      ),
    );
  }

  void _deleteAccount() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("CẢNH BÁO XÓA TÀI KHOẢN", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text("Việc xóa tài khoản sẽ tiến hành:\n\n- Xóa vĩnh viễn Lịch trình cá nhân.\n- Giải tán nhóm bạn làm Quản trị.\n- Rời khỏi các nhóm đang tham gia.\n- Hủy toàn bộ danh bạ bạn bè.\n- Xóa toàn bộ tin nhắn đã gửi.\n\nBạn có chắc chắn muốn thực hiện?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Đồng ý xóa", style: TextStyle(color: Colors.white))),
        ],
      ),
    );

    if (confirm != true) return;

    if (user == null) return;
    String providerId = user!.providerData.isNotEmpty ? user!.providerData.first.providerId : 'unknown';

    try {
      if (providerId == 'password') {
        final passController = TextEditingController();
        bool? authConfirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                title: const Text("Xác thực bảo mật"),
                content: TextField(controller: passController, decoration: const InputDecoration(labelText: "Nhập mật khẩu hiện tại"), obscureText: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Xác nhận"))
                ]
            )
        );
        if (authConfirm == true) {
          AuthCredential credential = EmailAuthProvider.credential(email: user!.email!, password: passController.text);
          await user!.reauthenticateWithCredential(credential);
          await _performDelete();
        }
      } else if (providerId == 'google.com') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser != null) {
          final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
          AuthCredential credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
          await user!.reauthenticateWithCredential(credential);
          await _performDelete();
        }
      } else if (providerId == 'phone' || user!.phoneNumber != null) {
        _verifyPhoneForReauth(user!.phoneNumber!);
      } else {
        _showMsg("Lỗi: Không tìm thấy phương thức xác thực.");
      }
    } catch (e) {
      _showMsg("Xác thực thất bại. Vui lòng thử lại.");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Cài đặt tài khoản")),
      body: isLoading
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.red),
            const SizedBox(height: 20),
            Text(loadingText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            const Text("Vui lòng không tắt ứng dụng...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: isDarkMode ? Colors.yellow : Colors.orange,
                size: 30
            ),
            title: const Text("Chế độ tối", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: const Text("Thay đổi giao diện ứng dụng"),
            trailing: Switch(
              value: isDarkMode,
              activeColor: Colors.red,
              onChanged: (value) async {
                setState(() {
                  themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                });
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isDarkTheme', value);
              },
            ),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red, size: 30),
            title: const Text("Xóa tài khoản", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: const Text("Xóa vĩnh viễn tài khoản và dữ liệu liên quan"),
            onTap: _deleteAccount,
          ),
          const Divider(),
        ],
      ),
    );
  }
}