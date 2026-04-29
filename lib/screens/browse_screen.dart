import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 👉 THÊM FIRESTORE
import '../database/db_helper.dart';
import 'task_detail_list_screen.dart';
import 'friends_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DBHelper dbHelper = DBHelper();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;

  int totalTasks = 0;
  int completedTasks = 0;
  String? savedApiKey;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadApiKey();
  }

  void _loadStats() async {
    final tasks = await dbHelper.getAllTasks();
    if (!mounted) return;
    setState(() {
      totalTasks = tasks.length;
      completedTasks = tasks.where((t) => t['isCompleted'] == 1).length;
    });
  }

  void _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      savedApiKey = prefs.getString('gemini_api_key');
    });
  }

  void _saveApiKey() async {
    TextEditingController keyController = TextEditingController(text: savedApiKey);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cài đặt Gemini API Key"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Để sử dụng Trợ lý AI, bạn cần nhập API Key của riêng mình (Miễn phí từ Google AI Studio).", style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(hintText: "Nhập API Key bắt đầu bằng AIza..."),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              if (keyController.text.trim().isEmpty) {
                await prefs.remove('gemini_api_key');
              } else {
                await prefs.setString('gemini_api_key', keyController.text.trim());
              }
              _loadApiKey();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Lưu"),
          )
        ],
      ),
    );
  }

  void showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  // 🔥 HÀM MỚI: XỬ LÝ KHI ĐĂNG NHẬP THÀNH CÔNG (TẠO PROFILE & SYNC CLOUD)
  Future<void> _onLoginSuccess(User user) async {
    try {
      // 1. Lưu thông tin người dùng vào Bảng 'users'
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'phone': user.phoneNumber ?? '',
        'displayName': user.displayName ?? '',
        'lastLogin': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true)); // merge: true để không ghi đè mất data cũ

      // 2. Đồng bộ các công việc vừa tạo Offline lên Cloud
      await dbHelper.syncLocalToCloud();

      // 3. Tải lại bảng thống kê
      _loadStats();
    } catch (e) {
      debugPrint("Lỗi đồng bộ Cloud: $e");
    }
  }

  void submitAuth() async {
    if (emailController.text.isEmpty || passController.text.isEmpty) {
      showMsg("Vui lòng nhập Email và Mật khẩu!");
      return;
    }
    setState(() => isLoading = true);
    try {
      if (isLoginMode) {
        UserCredential cred = await _auth.signInWithEmailAndPassword(email: emailController.text.trim(), password: passController.text.trim());
        if (cred.user != null) await _onLoginSuccess(cred.user!);
      } else {
        UserCredential cred = await _auth.createUserWithEmailAndPassword(email: emailController.text.trim(), password: passController.text.trim());
        await cred.user?.sendEmailVerification();
        if (cred.user != null) await _onLoginSuccess(cred.user!);
        showMsg("Đăng ký thành công! Hãy kiểm tra Gmail để xác thực.");
      }
    } on FirebaseAuthException catch (e) {
      String errorText = "Lỗi: ${e.message}";
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') errorText = "Tài khoản hoặc mật khẩu không đúng.";
      else if (e.code == 'email-already-in-use') errorText = "Email này đã được đăng ký từ trước.";
      else if (e.code == 'weak-password') errorText = "Mật khẩu phải có ít nhất 6 ký tự.";
      else if (e.code == 'invalid-email') errorText = "Định dạng Email không hợp lệ.";
      showMsg(errorText);
    } catch (e) {
      showMsg("Lỗi hệ thống: $e");
    }
    if (mounted) setState(() => isLoading = false);
  }

  void resetPassword() async {
    if (emailController.text.isEmpty) {
      showMsg("Vui lòng nhập Email để lấy lại mật khẩu!");
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: emailController.text.trim());
      showMsg("Link đặt lại mật khẩu đã được gửi vào Gmail!");
    } catch (e) {
      showMsg("Lỗi gửi mail: Vui lòng kiểm tra lại địa chỉ Email.");
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() => isLoading = true);
    try {
      await GoogleSignIn().signOut();
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
        UserCredential cred = await _auth.signInWithCredential(credential);
        if (cred.user != null) await _onLoginSuccess(cred.user!);
      }
    } catch (e) {
      showMsg("Lỗi: Hãy chắc chắn máy ảo có Google Play và bạn đã thêm SHA-1.");
    }
    if (mounted) setState(() => isLoading = false);
  }

  void signInWithPhone() {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nhập số điện thoại"),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: "VD: 0912345678", prefixIcon: Icon(Icons.phone)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            onPressed: () async {
              String phone = phoneController.text.trim();
              if (phone.isEmpty) return;
              if (phone.startsWith('0')) phone = '+84${phone.substring(1)}';
              Navigator.pop(context);
              _verifyPhoneNumber(phone);
            },
            child: const Text("Gửi mã OTP"),
          )
        ],
      ),
    );
  }

  void _verifyPhoneNumber(String phoneNumber) async {
    setState(() => isLoading = true);
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        UserCredential cred = await _auth.signInWithCredential(credential);
        if (cred.user != null) await _onLoginSuccess(cred.user!);
        if (mounted) setState(() => isLoading = false);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) setState(() => isLoading = false);
        showMsg("Lỗi SMS (${e.code}).");
      },
      codeSent: (String verificationId, int? resendToken) {
        if (mounted) setState(() => isLoading = false);
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
      builder: (context) => AlertDialog(
        title: const Text("Nhập mã OTP"),
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
                UserCredential cred = await _auth.signInWithCredential(credential);
                if (cred.user != null) await _onLoginSuccess(cred.user!);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                showMsg("Mã OTP không hợp lệ hoặc đã hết hạn!");
              }
            },
            child: const Text("Xác nhận"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        User? user = snapshot.data;
        if (user == null) return buildAuthUI();
        if (!user.emailVerified && user.phoneNumber == null) return buildVerifyEmailUI(user);
        return buildProfileUI(user);
      },
    );
  }

  Widget buildAuthUI() {
    return Scaffold(
      appBar: AppBar(title: Text(isLoginMode ? "Đăng nhập" : "Tạo tài khoản mới")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.account_circle, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            TextField(controller: emailController, decoration: InputDecoration(labelText: "Email của bạn", prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            TextField(controller: passController, decoration: InputDecoration(labelText: "Mật khẩu (ít nhất 6 ký tự)", prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), obscureText: true),
            const SizedBox(height: 20),
            if (isLoading) const CircularProgressIndicator()
            else SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: submitAuth, child: Text(isLoginMode ? "ĐĂNG NHẬP" : "ĐỒNG Ý ĐĂNG KÝ", style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [TextButton(onPressed: () => setState(() => isLoginMode = !isLoginMode), child: Text(isLoginMode ? "Tạo tài khoản" : "Quay lại Đăng nhập")), if (isLoginMode) TextButton(onPressed: resetPassword, child: const Text("Quên mật khẩu?"))]),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.g_mobiledata, color: Colors.red, size: 30), label: const Text("Google", style: TextStyle(color: Colors.black87)), onPressed: signInWithGoogle)),
                const SizedBox(width: 15),
                Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.phone_android, color: Colors.blue), label: const Text("Số ĐT", style: TextStyle(color: Colors.black87)), onPressed: signInWithPhone)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget buildVerifyEmailUI(User user) {
    return Scaffold(
      appBar: AppBar(title: const Text("Xác thực Email")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              Text("Vui lòng vào hộp thư ${user.email} và bấm vào Link xác thực.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 30),
              ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text("Đã xác thực xong? Tải lại ngay"), onPressed: () async { await user.reload(); setState(() {}); }),
              TextButton(onPressed: () async { await _auth.signOut(); setState(() => isLoginMode = true); }, child: const Text("Đăng xuất & Quay lại", style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildProfileUI(User user) {
    String displayName = user.phoneNumber ?? user.email ?? user.displayName ?? "Người dùng ẩn danh";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hồ sơ & Thống kê"),
        actions: [IconButton(icon: const Icon(Icons.exit_to_app), onPressed: () async => await _auth.signOut())],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, backgroundColor: Colors.red, child: Icon(Icons.person, size: 50, color: Colors.white)),
            const SizedBox(height: 15),
            Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
              child: Text(user.phoneNumber != null ? "Đăng nhập bằng SĐT" : "Đã xác thực", style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(height: 30),

            Card(
              elevation: 0,
              color: savedApiKey == null ? Colors.orange.shade50 : Colors.blue.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: savedApiKey == null ? Colors.orange.shade200 : Colors.blue.shade200)),
              child: ListTile(
                leading: Icon(Icons.vpn_key, color: savedApiKey == null ? Colors.orange : Colors.blue),
                title: const Text("Gemini API Key", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(savedApiKey == null ? "Chưa cài đặt (AI đang khóa)" : "Đã cấu hình an toàn"),
                trailing: const Icon(Icons.edit),
                onTap: _saveApiKey,
              ),
            ),
            const SizedBox(height: 15),

            // 🔥 THÊM NÚT DANH BẠ KẾT BẠN Ở ĐÂY
            Card(
              elevation: 0,
              color: Colors.pink.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.pink.shade200)),
              child: ListTile(
                leading: const Icon(Icons.group, color: Colors.pink),
                title: const Text("Bạn bè & Danh bạ", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Tìm kiếm, kết bạn qua SĐT/Email"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen()));
                },
              ),
            ),
            const SizedBox(height: 30),
            const Align(alignment: Alignment.centerLeft, child: Text("Bảng thống kê cá nhân", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _buildStatCard("Tổng công việc", totalTasks.toString(), Colors.blue, Icons.assignment, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailListScreen(listType: 'ALL', title: "Tất cả công việc"))).then((_) => _loadStats());
                })),
                const SizedBox(width: 16),
                Expanded(child: _buildStatCard("Đã hoàn thành", completedTasks.toString(), Colors.green, Icons.task_alt, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailListScreen(listType: 'COMPLETED', title: "Công việc đã xong"))).then((_) => _loadStats());
                })),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard("Đang xử lý", (totalTasks - completedTasks).toString(), Colors.orange, Icons.pending_actions, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskDetailListScreen(listType: 'PENDING', title: "Công việc đang xử lý"))).then((_) => _loadStats());
                })),
              ],
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                onPressed: () async {
                  await GoogleSignIn().signOut();
                  await _auth.signOut();
                },
                child: const Text("ĐĂNG XUẤT TÀI KHOẢN"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withAlpha(80))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(value, style: TextStyle(fontSize: 32, color: color, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}