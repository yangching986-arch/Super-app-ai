import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

class Session {
  static final token = ValueNotifier<String?>(null);
  static final role = ValueNotifier<String>('user');
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token.value = p.getString('token');
    role.value = p.getString('role') ?? 'user';
  }
  static Future<void> save(String t, [String userRole = 'user']) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t); await p.setString('role', userRole);
    token.value = t; role.value = userRole;
  }
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token'); await p.remove('role');
    token.value = null; role.value = 'user';
  }
  static Map<String,String> headers() => {
    'Content-Type':'application/json',
    if (token.value != null) 'Authorization':'Bearer ${token.value}',
  };
}

class AuthGate extends StatefulWidget {
  final Widget Function() child;
  const AuthGate({super.key,required this.child});
  @override
  State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  bool ready = false;
  @override
  void initState() { super.initState(); Session.load().then((_) { if (mounted) setState(() => ready=true); }); }
  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return ValueListenableBuilder<String?>(valueListenable:Session.token,
      builder:(_,t,__) => t == null ? const LoginPage() : widget.child());
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final name=TextEditingController(), email=TextEditingController(), pass=TextEditingController();
  bool register=false,busy=false;
  String? error;
  @override
  void dispose() { name.dispose();email.dispose();pass.dispose();super.dispose(); }
  Future<void> submit() async {
    setState(() { busy=true;error=null; });
    try {
      final body={'email':email.text.trim(),'password':pass.text,if(register)'name':name.text.trim()};
      final r=await http.post(Uri.parse('$baseUrl/auth/${register?'register':'login'}'),
        headers:{'Content-Type':'application/json'},body:jsonEncode(body)).timeout(const Duration(seconds:20));
      final d=jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode==200) { await Session.save(d['token'],d['role'] ?? 'user');return; }
      error=d['detail'] is String ? d['detail'] : 'তথ্য ঠিকভাবে দিন।';
    } catch (_) { error='Backend-এ সংযোগ হয়নি। API_URL ও সার্ভার পরীক্ষা করুন।'; }
    if(mounted)setState(()=>busy=false);
  }
  InputDecoration deco(String h)=>InputDecoration(hintText:h,filled:true,fillColor:panel,
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:const BorderSide(color:line)),
    enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:const BorderSide(color:line)));
  @override
  Widget build(BuildContext context)=>Scaffold(backgroundColor:bg,body:SafeArea(child:Center(child:SingleChildScrollView(
    padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:400),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Icon(Icons.auto_awesome,size:48,color:Color(0xFF7C8CFF)),
        const SizedBox(height:12),
        const Text('Hybrid AI Super App',textAlign:TextAlign.center,style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
        const SizedBox(height:6),Text(register?'নতুন অ্যাকাউন্ট খুলুন':'লগইন করুন',textAlign:TextAlign.center,style:const TextStyle(color:mut)),
        const SizedBox(height:22),
        if(register)...[TextField(controller:name,decoration:deco('নাম')),const SizedBox(height:10)],
        TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:deco('ইমেইল')),
        const SizedBox(height:10),
        TextField(controller:pass,obscureText:true,onSubmitted:(_)=>submit(),decoration:deco('পাসওয়ার্ড (কমপক্ষে ৮ অক্ষর)')),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(error!,style:const TextStyle(color:badC))),
        const SizedBox(height:16),FilledButton(onPressed:busy?null:submit,style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48)),
          child:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):Text(register?'অ্যাকাউন্ট খুলুন':'লগইন')),
        TextButton(onPressed:busy?null:()=>setState(() { register = !register; error = null; }),
          child:Text(register?'আগে থেকেই অ্যাকাউন্ট আছে? লগইন':'নতুন? অ্যাকাউন্ট খুলুন'))
      ]))))));
}
