import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth.dart';
import 'app_config.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Hybrid AI Super App',
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: acc), useMaterial3: true),
    home: AuthGate(child: () => const ChatPage()),
  );
}

class AiModel {
  final String id, name, status;
  AiModel(this.id, this.name, this.status);
}
class Msg {
  final String text;
  final bool me;
  final String? tag;
  final bool fallback;
  Msg(this.text, this.me, {this.tag, this.fallback = false});
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<AiModel> models = [];
  String? selected;
  bool freeOnly = true, loading = false, codingAgent = false;
  final msgs = <Msg>[Msg('হ্যালো! মডেল বেছে নিন, অথবা Smart Router ব্যবহার করুন।', false)];
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  final sk = GlobalKey<ScaffoldState>();
  int? convId;
  List convs = [];

  @override
  void initState() {
    super.initState();
    loadModels();
    loadConvs();
  }
  @override
  void dispose() {
    ctrl.dispose(); scroll.dispose(); super.dispose();
  }

  Future<void> loadModels() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/models'), headers: Session.headers()).timeout(const Duration(seconds: 12));
      if (r.statusCode == 401) { await Session.clear(); return; }
      if (r.statusCode != 200) return;
      final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      if (mounted) setState(() => models = [for (final m in list) AiModel(m['id'], m['name'], m['status'])]);
    } catch (_) {}
  }

  Future<void> send() async {
    final q = ctrl.text.trim();
    if (q.isEmpty || loading) return;
    ctrl.clear();
    setState(() { msgs.add(Msg(q, true)); loading = true; });
    toEnd();
    try {
      final r = await http.post(Uri.parse('$baseUrl/chat'), headers: Session.headers(),
        body: jsonEncode({'message': q, 'model': selected, 'free_only': freeOnly,
          'conversation_id': convId, 'coding_agent': codingAgent})).timeout(const Duration(seconds: 120));
      if (r.statusCode == 401) { await Session.clear(); return; }
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode >= 400) throw Exception(d['detail'] ?? 'Request failed');
      convId = d['conversation_id'] ?? convId;
      final tried = (d['tried'] as List? ?? []).join(', ');
      if (d['answer'] == null) {
        msgs.add(Msg(d['error'] ?? 'কোনো মডেল এখন উত্তর দিচ্ছে না। পরে আবার চেষ্টা করুন।', false));
      } else {
        final tag = d['fallback'] == true ? '$tried ব্যস্ত → ${d['model']}' : 'উত্তর দিয়েছে: ${d['model']}';
        msgs.add(Msg(d['answer'], false, tag: codingAgent ? 'Coding Agent · $tag' : tag, fallback: d['fallback'] == true));
      }
    } catch (e) {
      msgs.add(Msg('সমস্যা হয়েছে: ${e.toString().replaceFirst('Exception: ', '')}', false));
    }
    if (!mounted) return;
    setState(() => loading = false);
    loadModels(); loadConvs(); toEnd();
  }

  void toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent + 100,
      duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  });

  Future<void> loadConvs() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/conversations'), headers: Session.headers());
      if (r.statusCode == 401) { await Session.clear(); return; }
      if (r.statusCode == 200 && mounted) setState(() => convs = jsonDecode(utf8.decode(r.bodyBytes)) as List);
    } catch (_) {}
  }
  Future<void> openConv(int id) async {
    Navigator.pop(context);
    try {
      final r = await http.get(Uri.parse('$baseUrl/conversations/$id'), headers: Session.headers());
      if (r.statusCode != 200) throw Exception('চ্যাট খোলা যায়নি');
      final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      setState(() {
        convId = id; codingAgent = false;
        msgs..clear()..addAll([for (final m in list) Msg(m['content'], m['role'] == 'user',
          tag: m['model'] != null ? 'উত্তর দিয়েছে: ${m['model']}' : null)]);
      });
      toEnd();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> deleteConv(int id) async {
    await http.delete(Uri.parse('$baseUrl/conversations/$id'), headers: Session.headers());
    if (convId == id) newChat();
    loadConvs();
  }
  void newChat() => setState(() {
    convId = null; msgs..clear()..add(Msg('নতুন চ্যাট শুরু হয়েছে। কী জানতে চান?', false));
  });

  Color statusColor(String s) => (s == 'free' || s == 'configured') ? okC : (s == 'limited' ? warnC : badC);
  String statusLabel(String s) => s == 'free' ? 'Free' : s == 'configured' ? 'Ready' : s == 'limited' ? 'Limit' : 'Key লাগবে';

  Widget drawer() => Drawer(backgroundColor: panel, child: SafeArea(child: Column(children: [
    const ListTile(leading: Icon(Icons.auto_awesome, color: acc), title: Text('Hybrid AI Super App', style: TextStyle(fontWeight: FontWeight.bold))),
    ListTile(leading: const Icon(Icons.add), title: const Text('নতুন চ্যাট'), onTap: () { Navigator.pop(context); newChat(); }),
    ListTile(leading: const Icon(Icons.key), title: const Text('নিজের API Key'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeysPage())).then((_) => loadModels()); }),
    ListTile(leading: const Icon(Icons.code), title: const Text('Coding Agent'), onTap: () { Navigator.pop(context); setState(() { codingAgent = true; newChat(); }); }),
    if (Session.role.value == 'admin')
      ListTile(leading: const Icon(Icons.admin_panel_settings), title: const Text('Admin Dashboard'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage())); }),
    const Divider(color: line),
    const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.fromLTRB(16,8,16,4), child: Text('আপনার চ্যাট', style: TextStyle(color: mut)))),
    Expanded(child: convs.isEmpty ? const Center(child: Text('এখনো কোনো চ্যাট নেই', style: TextStyle(color: mut))) :
      ListView(children: [for (final c in convs) ListTile(
        selected: c['id'] == convId, title: Text(c['title'] ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => deleteConv(c['id'])),
        onTap: () => openConv(c['id']))])),
    const Divider(color: line),
    ListTile(leading: const Icon(Icons.logout), title: const Text('লগআউট'), onTap: Session.clear),
  ])));

  Widget chip(AiModel m) {
    final on = selected == m.id;
    final locked = m.status == 'needs_key' || m.status == 'limited';
    return Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (locked) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m.status == 'needs_key'
            ? '${m.name}-এর জন্য Settings থেকে নিজের API Key যোগ করুন।' : '${m.name} সাময়িকভাবে সীমিত।')));
          return;
        }
        if (m.status == 'configured' && freeOnly) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('নিজের API Key ব্যবহার করতে Free-Only বন্ধ করুন।')));
          return;
        }
        setState(() => selected = on ? null : m.id);
      },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: on ? const Color(0xFF1D2340) : panel,
          border: Border.all(color: on ? acc : line), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [CircleAvatar(radius: 4, backgroundColor: statusColor(m.status)),
          const SizedBox(width: 6), Text(m.name, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6), Text(statusLabel(m.status), style: const TextStyle(fontSize: 11, color: mut))]))));
  }
  Widget bubble(Msg m) => Align(alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .88),
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(color: m.me ? acc : panel, border: m.me ? null : Border.all(color: line), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(m.text, style: TextStyle(fontSize: 15, height: 1.5, color: m.me ? bg : null)),
        if (m.tag != null) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(m.tag!, style: TextStyle(fontSize: 12, color: m.fallback ? warnC : okC)))
      ])));

  @override
  Widget build(BuildContext context) => Scaffold(key: sk, drawer: drawer(), body: SafeArea(child: Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(12,10,12,2), child: Row(children: [
      IconButton(icon: const Icon(Icons.menu), onPressed: () => sk.currentState?.openDrawer()),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hybrid AI Super App', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        Text('Multi-model AI assistant', style: TextStyle(color: mut, fontSize: 12))])),
      IconButton(tooltip: 'API Keys', icon: const Icon(Icons.key), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiKeysPage())).then((_) => loadModels())),
    ])),
    SizedBox(height: 46, child: models.isEmpty ? const Center(child: Text('মডেল লোড হচ্ছে…', style: TextStyle(color: mut))) :
      ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), children: [for (final m in models) chip(m)])),
    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: Row(children: [
      const Text('Free-Only', style: TextStyle(color: mut, fontSize: 12)),
      Switch(value: freeOnly, onChanged: (v) => setState(() => freeOnly = v)),
      const SizedBox(width: 12),
      const Text('Coding Agent', style: TextStyle(color: mut, fontSize: 12)),
      Switch(value: codingAgent, onChanged: (v) => setState(() => codingAgent = v)),
    ])),
    Expanded(child: ListView.builder(controller: scroll, padding: const EdgeInsets.all(16),
      itemCount: msgs.length + (loading ? 1 : 0), itemBuilder: (_, i) => i == msgs.length ? const Dots() : bubble(msgs[i]))),
    Container(decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
      padding: const EdgeInsets.fromLTRB(14,9,14,10), child: Row(children: [
        Expanded(child: TextField(controller: ctrl, minLines: 1, maxLines: 5, onSubmitted: (_) => send(),
          decoration: InputDecoration(hintText: codingAgent ? 'কোডিংয়ের কাজ লিখুন…' : 'প্রশ্ন লিখুন…', filled: true, fillColor: panel,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line))))),
        const SizedBox(width: 8), FilledButton(onPressed: loading ? null : send,
          style: FilledButton.styleFrom(minimumSize: const Size(55,48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Icon(Icons.send))
      ]))
  ])));
}

class ApiKeysPage extends StatefulWidget {
  const ApiKeysPage({super.key});
  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}
class _ApiKeysPageState extends State<ApiKeysPage> {
  final claude = TextEditingController(), grok = TextEditingController();
  bool busy = false, hideClaude = true, hideGrok = true;
  List keys = [];
  String? error;
  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { claude.dispose(); grok.dispose(); super.dispose(); }
  Future<void> refresh() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/keys'), headers: Session.headers());
      if (r.statusCode == 200 && mounted) setState(() => keys = jsonDecode(utf8.decode(r.bodyBytes)) as List);
      else if (r.statusCode >= 400) throw Exception('API Key list পাওয়া যায়নি');
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  bool configured(String provider) => keys.any((e) => e['provider'] == provider);
  Future<void> save(String provider, TextEditingController c) async {
    if (c.text.trim().length < 8) { setState(() => error = 'সঠিক API Key দিন।'); return; }
    setState(() { busy = true; error = null; });
    try {
      final r = await http.put(Uri.parse('$baseUrl/keys'), headers: Session.headers(),
        body: jsonEncode({'provider':provider,'api_key':c.text.trim()}));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode >= 400) throw Exception(d['detail'] ?? 'Key save failed');
      c.clear(); await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Key নিরাপদে সংরক্ষণ করা হয়েছে।')));
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    if (mounted) setState(() => busy = false);
  }
  Future<void> remove(String provider) async {
    setState(() { busy = true; error = null; });
    try {
      final r = await http.delete(Uri.parse('$baseUrl/keys/$provider'), headers: Session.headers());
      if (r.statusCode >= 400) throw Exception('Key delete failed');
      await refresh();
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    if (mounted) setState(() => busy = false);
  }
  Widget keyCard(String provider, String label, TextEditingController c, bool hidden, VoidCallback toggle) =>
    Card(color: panel, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        Icon(configured(provider) ? Icons.check_circle : Icons.info_outline, color: configured(provider) ? okC : warnC),
        const SizedBox(width: 6), Text(configured(provider) ? 'যুক্ত আছে' : 'যুক্ত নেই', style: const TextStyle(color: mut))]),
      const SizedBox(height: 12),
      TextField(controller: c, obscureText: hidden, autocorrect: false, enableSuggestions: false,
        decoration: InputDecoration(hintText: 'আপনার $label API Key', suffixIcon: IconButton(icon: Icon(hidden ? Icons.visibility : Icons.visibility_off), onPressed: toggle))),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: FilledButton(onPressed: busy ? null : () => save(provider,c), child: const Text('Save Key'))),
        if (configured(provider)) ...[const SizedBox(width: 8), OutlinedButton(onPressed: busy ? null : () => remove(provider), child: const Text('Remove'))]])
    ])));
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('নিজের API Key')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('আপনার API Key সার্ভারে encrypted অবস্থায় সংরক্ষণ হবে। কোনো key chat বা screen-এ আবার দেখানো হবে না।', style: TextStyle(color: mut, height: 1.5)),
      const SizedBox(height: 14),
      keyCard('claude','Claude',claude,hideClaude,() => setState(() => hideClaude = !hideClaude)),
      keyCard('grok','Grok',grok,hideGrok,() => setState(() => hideGrok = !hideGrok)),
      if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: badC))),
      const SizedBox(height: 10),
      const Text('নোট: API Provider-এর usage ও billing তাদের নিজস্ব account অনুযায়ী প্রযোজ্য।', style: TextStyle(color: mut, fontSize: 12))
    ]));
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}
class _AdminPageState extends State<AdminPage> {
  Map stats = {};
  List users = [];
  bool busy = false;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { busy = true; error = null; });
    try {
      final rs = await Future.wait([
        http.get(Uri.parse('$baseUrl/admin/stats'), headers: Session.headers()),
        http.get(Uri.parse('$baseUrl/admin/users'), headers: Session.headers())
      ]);
      final sd = jsonDecode(utf8.decode(rs[0].bodyBytes));
      final ud = jsonDecode(utf8.decode(rs[1].bodyBytes));
      if (rs[0].statusCode >= 400 || rs[1].statusCode >= 400) throw Exception('Admin access denied বা server error');
      if (mounted) setState(() { stats = sd; users = ud as List; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    if (mounted) setState(() => busy = false);
  }
  Future<void> changeRole(int id, String role) async {
    try {
      final r = await http.put(Uri.parse('$baseUrl/admin/users/$id/role?role=$role'), headers: Session.headers());
      if (r.statusCode >= 400) throw Exception(jsonDecode(utf8.decode(r.bodyBytes))['detail'] ?? 'Role update failed');
      await load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> deleteUser(int id) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('User Delete করবেন?'), content: const Text('এই user-এর conversations, messages ও saved keys মুছে যাবে।'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Delete'))]));
    if (yes != true) return;
    try {
      final r = await http.delete(Uri.parse('$baseUrl/admin/users/$id'), headers: Session.headers());
      if (r.statusCode >= 400) throw Exception(jsonDecode(utf8.decode(r.bodyBytes))['detail'] ?? 'Delete failed');
      await load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Widget metric(String title, dynamic value, IconData icon) => Expanded(child: Card(color: panel, child: Padding(
    padding: const EdgeInsets.all(12), child: Column(children: [Icon(icon,color:acc), const SizedBox(height:7),
      Text('${value ?? 0}', style: const TextStyle(fontSize: 22,fontWeight: FontWeight.bold)),
      Text(title, style: const TextStyle(color:mut,fontSize:12))]))));
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Admin Dashboard'),
    actions: [IconButton(onPressed: busy ? null : load, icon: const Icon(Icons.refresh))]),
    body: busy && stats.isEmpty ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color:badC))),
        Row(children: [metric('Users',stats['users'],Icons.people), metric('Chats',stats['conversations'],Icons.forum), metric('Messages',stats['messages'],Icons.message)]),
        const Padding(padding: EdgeInsets.fromLTRB(4,18,4,8), child: Text('ব্যবহারকারী ব্যবস্থাপনা',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
        for (final u in users) Card(color:panel, child: ListTile(
          title: Text(u['name'] ?? 'Unknown'), subtitle: Text('${u['email']}\nID: ${u['id']} · ${u['role']}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(onSelected: (v) {
            if (v == 'delete') deleteUser(u['id']); else changeRole(u['id'],v);
          }, itemBuilder: (_) => [
            if (u['role'] != 'admin') const PopupMenuItem(value:'admin',child:Text('Make Admin')),
            if (u['role'] == 'admin') const PopupMenuItem(value:'user',child:Text('Make User')),
            const PopupMenuItem(value:'delete',child:Text('Delete User',style:TextStyle(color:badC)))
          ], child: const Icon(Icons.more_vert))
        ))
      ])));
}

class Dots extends StatefulWidget {
  const Dots({super.key});
  @override
  State<Dots> createState() => _DotsState();
}
class _DotsState extends State<Dots> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync:this,duration:const Duration(milliseconds:900))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(8), child: AnimatedBuilder(animation:c,
    builder: (_,__) => Row(mainAxisSize:MainAxisSize.min, children: [for (var i=0;i<3;i++)
      Container(width:7,height:7,margin:const EdgeInsets.only(right:4),
        decoration:BoxDecoration(shape:BoxShape.circle,color:mut.withOpacity(((c.value+i/3)%1)<.5?1:.35)))])));
}
