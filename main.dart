import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth.dart';

// Android emulator: 10.0.2.2 reaches your PC. Real phone: pass your PC's LAN IP:
// flutter run --dart-define=API_URL=http://192.168.0.10:8000
const baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');

const bg = Color(0xFF0D1019), panel = Color(0xFF151A28), line = Color(0xFF252C42);
const mut = Color(0xFF8B93AD), acc = Color(0xFF7C8CFF);
const okC = Color(0xFF4CC38A), warnC = Color(0xFFF0B35A), badC = Color(0xFFEF6B73);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Hybrid AI',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: acc),
        ),
        home: AuthGate(child: () => const ChatPage()),
      );
}

class AiModel {
  final String id, name, status; // status: free | limited | needs_key
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
  List<AiModel> models = [
    AiModel('gemini', 'Gemini Flash', 'free'),
    AiModel('groq', 'Llama 70B', 'free'),
    AiModel('cerebras', 'Cerebras', 'free'),
    AiModel('deepseek', 'DeepSeek', 'free'),
    AiModel('mistral', 'Mistral', 'free'),
    AiModel('claude', 'Claude', 'needs_key'),
    AiModel('grok', 'Grok', 'needs_key'),
  ];
  String? selected;
  bool freeOnly = true, loading = false;
  final msgs = <Msg>[Msg('হ্যালো! মডেল বেছে নিন, অথবা কিছু না বাছলে Smart Router নিজেই ফ্রি মডেল বাছবে।', false)];
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

  Future<void> loadModels() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/models')).timeout(const Duration(seconds: 8));
      final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      setState(() => models = [for (final m in list) AiModel(m['id'], m['name'], m['status'])]);
    } catch (_) {} // keep default list when the backend is offline
  }

  Future<void> send() async {
    final q = ctrl.text.trim();
    if (q.isEmpty || loading) return;
    ctrl.clear();
    setState(() {
      msgs.add(Msg(q, true));
      loading = true;
    });
    toEnd();
    try {
      final r = await http
          .post(Uri.parse('$baseUrl/chat'),
              headers: Session.headers(),
              body: jsonEncode({'message': q, 'model': selected, 'free_only': freeOnly, 'conversation_id': convId}))
          .timeout(const Duration(seconds: 90));
      if (r.statusCode == 401) {
        await Session.clear();
        return;
      }
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      convId = d['conversation_id'] ?? convId;
      final tried = (d['tried'] as List? ?? []).join(', ');
      if (d['answer'] == null) {
        msgs.add(Msg(d['error'] ?? 'কোনো ফ্রি মডেল এখন উত্তর দিচ্ছে না। এক মিনিট পরে আবার চেষ্টা করুন।', false));
      } else if (d['fallback'] == true) {
        msgs.add(Msg(d['answer'], false, tag: '$tried limit শেষ → ${d['model']} উত্তর দিয়েছে', fallback: true));
      } else {
        msgs.add(Msg(d['answer'], false, tag: 'উত্তর দিয়েছে: ${d['model']}'));
      }
    } catch (_) {
      msgs.add(Msg('Backend-এ সংযোগ হয়নি। সার্ভার চালু আছে কি না এবং API_URL ঠিক আছে কি না দেখুন।', false));
    }
    setState(() => loading = false);
    loadModels(); // refresh free / limited badges
    loadConvs();
    toEnd();
  }

  void toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent + 80,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  Future<void> loadConvs() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/conversations'), headers: Session.headers());
      if (r.statusCode == 401) return Session.clear();
      setState(() => convs = jsonDecode(utf8.decode(r.bodyBytes)) as List);
    } catch (_) {}
  }

  Future<void> openConv(int id) async {
    Navigator.pop(context);
    try {
      final r = await http.get(Uri.parse('$baseUrl/conversations/$id'), headers: Session.headers());
      final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      setState(() {
        convId = id;
        msgs
          ..clear()
          ..addAll([for (final m in list) Msg(m['content'], m['role'] == 'user', tag: m['model'] != null ? 'উত্তর দিয়েছে: ${m['model']}' : null)]);
      });
      toEnd();
    } catch (_) {}
  }

  Future<void> deleteConv(int id) async {
    await http.delete(Uri.parse('$baseUrl/conversations/$id'), headers: Session.headers());
    if (convId == id) newChat();
    loadConvs();
  }

  void newChat() => setState(() {
        convId = null;
        msgs
          ..clear()
          ..add(Msg('নতুন চ্যাট শুরু হয়েছে। কী জানতে চান?', false));
      });

  Widget drawer() => Drawer(
        backgroundColor: panel,
        child: SafeArea(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('নতুন চ্যাট'),
              onTap: () {
                Navigator.pop(context);
                newChat();
              },
            ),
            const Divider(color: line, height: 1),
            Expanded(
              child: convs.isEmpty
                  ? const Center(child: Text('এখনো কোনো চ্যাট নেই', style: TextStyle(color: mut)))
                  : ListView(children: [
                      for (final c in convs)
                        ListTile(
                          selected: c['id'] == convId,
                          title: Text(c['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => deleteConv(c['id'])),
                          onTap: () => openConv(c['id']),
                        ),
                    ]),
            ),
            const Divider(color: line, height: 1),
            ListTile(leading: const Icon(Icons.logout), title: const Text('লগআউট'), onTap: Session.clear),
          ]),
        ),
      );

  Color statusColor(String s) => s == 'free' ? okC : (s == 'limited' ? warnC : badC);
  String statusLabel(String s) => s == 'free' ? 'Free' : (s == 'limited' ? 'Limit শেষ' : 'Key লাগবে');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: sk,
      drawer: drawer(),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.menu), onPressed: () => sk.currentState?.openDrawer()),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hybrid AI Super App', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text('শুধু ফ্রি API ব্যবহার হয়', style: TextStyle(color: mut, fontSize: 13)),
                ]),
              ),
              const Text('Free-Only', style: TextStyle(color: mut, fontSize: 12)),
              Switch(value: freeOnly, onChanged: (v) => setState(() => freeOnly = v)),
            ]),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [for (final m in models) chip(m)],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              itemCount: msgs.length + (loading ? 1 : 0),
              itemBuilder: (_, i) => i == msgs.length ? const Dots() : bubble(msgs[i]),
            ),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  onSubmitted: (_) => send(),
                  decoration: InputDecoration(
                    hintText: 'প্রশ্ন লিখুন…',
                    filled: true,
                    fillColor: panel,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: loading ? null : send,
                style: FilledButton.styleFrom(minimumSize: const Size(56, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('পাঠান'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget chip(AiModel m) {
    final on = selected == m.id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: m.status == 'needs_key' ? 0.6 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (m.status == 'needs_key' && freeOnly) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${m.name}-এর ফ্রি API নেই। Free-Only বন্ধ করে নিজের Key দিন।')));
              return;
            }
            setState(() => selected = on ? null : m.id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? const Color(0xFF1D2340) : panel,
              border: Border.all(color: on ? acc : line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              CircleAvatar(radius: 4, backgroundColor: statusColor(m.status)),
              const SizedBox(width: 6),
              Text(m.name, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(statusLabel(m.status), style: const TextStyle(fontSize: 11, color: mut)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget bubble(Msg m) => Align(
        alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: m.me ? acc : panel,
            border: m.me ? null : Border.all(color: line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(m.text, style: TextStyle(fontSize: 15, height: 1.5, color: m.me ? bg : null)),
            if (m.tag != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(m.tag!, style: TextStyle(fontSize: 12, color: m.fallback ? warnC : okC)),
              ),
          ]),
        ),
      );
}

class Dots extends StatefulWidget {
  const Dots({super.key});
  @override
  State<Dots> createState() => _DotsState();
}

class _DotsState extends State<Dots> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mut.withOpacity(((c.value + i / 3) % 1) < 0.5 ? 1 : 0.35),
                ),
              ),
          ]),
        ),
      );
}
