import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show baseUrl, bg, panel, line, mut, badC;

class Session {
  static final token = ValueNotifier<String?>(null);
  static Future<void> load() async =>
      token.value = (await SharedPreferences.getInstance()).getString('token');
  static Future<void> save(String t) async {
    await (await SharedPreferences.getInstance()).setString('token', t);
    token.value = t;
  }

  static Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove('token');
    token.value = null;
  }

  static Map<String, String> headers() => {
        'Content-Type': 'application/json',
        if (token.value != null) 'Authorization': 'Bearer ${token.value}',
      };
}

class AuthGate extends StatefulWidget {
  final Widget Function() child;
  const AuthGate({super.key, required this.child});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool ready = false;
  @override
  void initState() {
    super.initState();
    Session.load().then((_) => setState(() => ready = true));
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ValueListenableBuilder<String?>(
      valueListenable: Session.token,
      builder: (_, t, __) => t == null ? const LoginPage() : widget.child(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController();
  bool register = false, busy = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = {'email': email.text, 'password': pass.text, if (register) 'name': name.text};
      final r = await http
          .post(Uri.parse('$baseUrl/auth/${register ? 'register' : 'login'}'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode == 200) {
        await Session.save(d['token']);
        return;
      }
      error = d['detail'] is String ? d['detail'] : 'তথ্য ঠিকভাবে দিন।';
    } catch (_) {
      error = 'Backend-এ সংযোগ হয়নি। সার্ভার চালু আছে কি না দেখুন।';
    }
    if (mounted) setState(() => busy = false);
  }

  InputDecoration deco(String h) => InputDecoration(
        hintText: h,
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Hybrid AI Super App', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(register ? 'নতুন অ্যাকাউন্ট খুলুন' : 'লগইন করুন', style: const TextStyle(color: mut)),
                  const SizedBox(height: 20),
                  if (register) ...[TextField(controller: name, decoration: deco('নাম')), const SizedBox(height: 10)],
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: deco('ইমেইল')),
                  const SizedBox(height: 10),
                  TextField(controller: pass, obscureText: true, onSubmitted: (_) => submit(), decoration: deco('পাসওয়ার্ড (কমপক্ষে ৮ অক্ষর)')),
                  if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: badC))),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(register ? 'অ্যাকাউন্ট খুলুন' : 'লগইন'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      register = !register;
                      error = null;
                    }),
                    child: Text(register ? 'আগে থেকেই অ্যাকাউন্ট আছে? লগইন' : 'নতুন? অ্যাকাউন্ট খুলুন'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
