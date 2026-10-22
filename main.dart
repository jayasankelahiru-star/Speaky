import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'SpeakUp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF5B4BFF), useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF5B4BFF), brightness: Brightness.dark, useMaterial3: true),
        home: const Home(),
      );
}

class Lesson {
  final String id, title, tip, task;
  final int min;
  const Lesson(this.id, this.title, this.tip, this.task, this.min);
}

const levels = ['Level 1 · Foundations', 'Level 2 · Structure & Delivery', 'Level 3 · Mastery'];
const lessons = [
  Lesson('1a', 'Introduce yourself', 'Breathe and speak at 120-150 words per minute.', 'Introduce yourself in 30-60 seconds: name, what you do, one interesting fact.', 20),
  Lesson('1b', 'Cut the filler words', 'Replace "um" and "like" with a silent pause.', 'Describe your favorite place for 45 seconds without filler words.', 25),
  Lesson('1c', 'Pace and volume', 'Pause after key points. Emphasize important words.', 'Explain how to make a cup of tea with deliberate pauses (about 45 seconds).', 25),
  Lesson('2a', 'Strong opening', 'Open with a question, a story or a surprising fact.', 'Give a 1-2 minute talk on a topic you love. Start with a strong hook.', 50),
  Lesson('2b', 'Tell a story', 'Situation, problem, turning point, lesson.', 'Tell a 2-minute story about a challenge you overcame and what you learned.', 60),
  Lesson('2c', 'Intro, body, conclusion', 'Tell them what you will say, say it, then recap.', 'Give a 2-minute talk with 3 clear points on why people should learn a new skill.', 70),
  Lesson('3a', 'Persuade', 'Claim, evidence, emotional appeal, call to action.', 'Persuade your audience to adopt one good habit, with evidence and a call to action (2-3 minutes).', 80),
  Lesson('3b', 'Pitch your idea', 'Problem, solution, market, ask.', 'Pitch a product or business idea to investors in 3 minutes.', 80),
  Lesson('3c', 'Full presentation', 'Combine everything: hook, structure, evidence, close.', 'Deliver a full 4-5 minute presentation on any topic, as if on stage.', 85),
];
const fillers = ['um', 'uh', 'umm', 'uhh', 'like', 'you know', 'basically', 'actually', 'literally', 'i mean', 'kind of', 'sort of'];

num n(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
List<String> L(dynamic x) => ((x as List?) ?? []).map((e) => e.toString()).toList();
String fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
String dayStr(DateTime d) => d.toIso8601String().substring(0, 10);

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0, xp = 0, streak = 0, secs = 0;
  SharedPreferences? sp;
  Map<String, int> done = {};
  List<Map<String, dynamic>> hist = [];
  String last = '', name = '', apiKey = '', aiLang = 'en', speechLang = 'en_US', err = '';
  Lesson cur = lessons[0];
  Map<String, dynamic>? view;
  bool busy = false, want = false, avail = false;
  final tx = TextEditingController(), keyC = TextEditingController(), nameC = TextEditingController();
  final stt = SpeechToText();
  Timer? timer;
  String base = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    sp = await SharedPreferences.getInstance();
    final s = sp!.getString('st');
    if (s != null) {
      final m = jsonDecode(s);
      xp = m['xp'] ?? 0;
      streak = m['streak'] ?? 0;
      last = m['last'] ?? '';
      name = m['name'] ?? '';
      apiKey = m['key'] ?? '';
      aiLang = m['ai'] ?? 'en';
      speechLang = m['sl'] ?? 'en_US';
      done = Map<String, int>.from(m['done'] ?? {});
      hist = List<Map<String, dynamic>>.from((m['hist'] ?? []).map((e) => Map<String, dynamic>.from(e)));
    }
    keyC.text = apiKey;
    nameC.text = name;
    setState(() {});
  }

  void save() => sp?.setString('st', jsonEncode({'xp': xp, 'streak': streak, 'last': last, 'name': name, 'key': apiKey, 'ai': aiLang, 'sl': speechLang, 'done': done, 'hist': hist}));

  bool unlocked(int i) => i == 0 || (done[lessons[i - 1].id] ?? 0) >= lessons[i - 1].min;

  // ---------- speech ----------
  Future<void> _listen() async {
    base = tx.text.trim();
    await stt.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => tx.text = base.isEmpty ? r.recognizedWords : '$base ${r.recognizedWords}');
      },
      localeId: speechLang,
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(seconds: 30),
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.dictation),
    );
  }

  Future<void> toggleRec() async {
    if (want) {
      want = false;
      timer?.cancel();
      await stt.stop();
      setState(() {});
      return;
    }
    setState(() => err = '');
    if (!avail) {
      avail = await stt.initialize(
        onStatus: (s) {
          if (s == 'done' && want && mounted) _listen();
        },
        onError: (e) {
          if (!mounted) return;
          if (e.permanent) want = false;
          setState(() => err = 'Speech error: ${e.errorMsg}');
        },
      );
    }
    if (!avail) {
      setState(() => err = 'Speech recognition unavailable. Allow the microphone permission and install Google speech services, or paste your transcript below.');
      return;
    }
    want = true;
    secs = 0;
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => secs++));
    setState(() {});
    await _listen();
  }

  // ---------- evaluation ----------
  Map<String, dynamic> metrics(String t) {
    final w = t.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
    final low = t.toLowerCase();
    final f = <String, int>{};
    var tot = 0;
    for (final k in fillers) {
      final c = RegExp('\\b${RegExp.escape(k)}\\b').allMatches(low).length;
      if (c > 0) {
        f[k] = c;
        tot += c;
      }
    }
    return {'w': w, 'tot': tot, 'f': f, 'secs': secs, 'wpm': secs > 3 ? (w / (secs / 60)).round() : null};
  }

  Future<void> evaluate() async {
    final t = tx.text.trim();
    if (apiKey.isEmpty) {
      setState(() => err = 'Add your Gemini API key in the Profile tab first.');
      return;
    }
    if (t.split(RegExp(r'\s+')).length < 8) {
      setState(() => err = 'Record or type at least a few sentences first.');
      return;
    }
    if (want) await toggleRec();
    setState(() {
      busy = true;
      err = '';
    });
    final m = metrics(t);
    try {
      final lang = aiLang == 'si' ? 'Sinhala (සිංහල)' : 'English';
      final prompt = 'You are a warm, expert public-speaking coach. Evaluate this speech transcript from a learner.\n'
          'Lesson: ${cur.title}. Task: ${cur.task}. Level ${cur.id[0]} of 3 (be stricter at higher levels).\n'
          'Measured: ${m['w']} words, ${m['secs']} seconds, WPM ${m['wpm'] ?? 'unknown'}, ${m['tot']} filler words ${jsonEncode(m['f'])}.\n'
          'The transcript comes from speech recognition, so ignore missing punctuation.\n'
          'Transcript:\n"""\n${t.length > 6000 ? t.substring(0, 6000) : t}\n"""\n'
          'Write all text values in $lang. Return ONLY JSON, no markdown: '
          '{"score":0-100,"clarity":0-100,"structure":0-100,"content":0-100,"delivery":0-100,"summary":"2 sentences","strengths":["..",".."],"improvements":["..",".."],"suggestions":["3 specific tips"],"drill":"one short drill","better_opening":"a stronger opening line"}';
      final res = await http
          .post(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent'),
              headers: {'x-goog-api-key': apiKey, 'content-type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.4}
              }))
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        final b = utf8.decode(res.bodyBytes);
        throw 'API error ${res.statusCode}: ${b.length > 200 ? b.substring(0, 200) : b}';
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final txt = (body['candidates'][0]['content']['parts'] as List).map((p) => p['text'] ?? '').join();
      final r = jsonDecode(txt.substring(txt.indexOf('{'), txt.lastIndexOf('}') + 1)) as Map<String, dynamic>;
      final score = n(r['score']).round().clamp(0, 100).toInt();
      final pl = hist.where((h) => h['lid'] == cur.id).toList();
      final prev = pl.isEmpty ? null : pl.last['score'];
      final first = !done.containsKey(cur.id);
      final pass = score >= cur.min;
      final gained = (score / 4).round() + ((pass && first) ? 15 : 0);
      done[cur.id] = max(done[cur.id] ?? 0, score);
      xp += gained;
      final today = dayStr(DateTime.now()), yest = dayStr(DateTime.now().subtract(const Duration(days: 1)));
      if (last != today) {
        streak = last == yest ? streak + 1 : 1;
        last = today;
      }
      hist.add({'lid': cur.id, 'lesson': cur.title, 'score': score, 'date': today});
      if (hist.length > 60) hist = hist.sublist(hist.length - 60);
      r['m'] = m;
      r['lesson'] = cur.title;
      r['lid'] = cur.id;
      r['pass'] = pass;
      r['xp'] = gained;
      r['prev'] = prev;
      r['min'] = cur.min;
      r['score'] = score;
      view = r;
      tab = 2;
      save();
    } catch (e) {
      err = 'Evaluation failed: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  // ---------- UI helpers ----------
  Widget pad(List<Widget> ch) => ListView(padding: const EdgeInsets.all(16), children: ch);
  Widget head(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)));
  Widget bar(String l, dynamic v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l), Text('${n(v).round()}', style: const TextStyle(fontWeight: FontWeight.bold))]),
          LinearProgressIndicator(value: n(v).clamp(0, 100) / 100, minHeight: 8, borderRadius: BorderRadius.circular(8)),
        ]),
      );
  Widget stat(String v, String l) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Column(children: [Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(l, style: const TextStyle(fontSize: 12))]))));
  Widget list(String t, List<String> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head(t), ...items.map((e) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $e')))]);

  // ---------- tabs ----------
  Widget learnPage() {
    final ch = <Widget>[Text('Hi${name.isEmpty ? '' : ' $name'} 👋', style: Theme.of(context).textTheme.headlineSmall), const Text('Reach the target score to unlock the next lesson.')];
    for (var l = 0; l < 3; l++) {
      ch.add(head(levels[l]));
      for (var j = 0; j < 3; j++) {
        final i = l * 3 + j, x = lessons[i], u = unlocked(i), d = (done[x.id] ?? 0) >= x.min;
        ch.add(Card(
            child: ListTile(
          enabled: u,
          leading: CircleAvatar(backgroundColor: d ? Colors.green : null, child: Icon(d ? Icons.check : (u ? Icons.play_arrow : Icons.lock))),
          title: Text(x.title),
          subtitle: Text('Target ${x.min}+${done[x.id] != null ? ' · best ${done[x.id]}' : ''}'),
          onTap: u ? () => setState(() { cur = x; tab = 1; }) : null,
        )));
      }
    }
    return pad(ch);
  }

  Widget practicePage() => pad([
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cur.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 6),
          Text('💡 ${cur.tip}'),
          const SizedBox(height: 6),
          Text(cur.task),
        ]))),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Speech language: '),
          DropdownButton<String>(value: speechLang, items: const [DropdownMenuItem(value: 'en_US', child: Text('English')), DropdownMenuItem(value: 'si_LK', child: Text('සිංහල'))], onChanged: want ? null : (v) { setState(() => speechLang = v!); save(); }),
        ]),
        Center(child: Column(children: [
          IconButton.filled(iconSize: 44, onPressed: toggleRec, icon: Icon(want ? Icons.stop : Icons.mic), style: IconButton.styleFrom(backgroundColor: want ? Colors.red : null, minimumSize: const Size(88, 88), shape: const CircleBorder())),
          Text(fmt(secs), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
          Text(want ? 'Listening… tap to stop' : 'Tap to record'),
        ])),
        const SizedBox(height: 12),
        TextField(controller: tx, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Transcript (edit or paste your own)')),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : evaluate, child: Padding(padding: const EdgeInsets.all(6), child: Text(busy ? 'Analyzing your speech…' : 'Evaluate my speech'))),
      ]);

  Widget feedbackPage() {
    final r = view;
    if (r == null) return pad([const Text('No evaluation yet. Finish a lesson in Practice to see your score and suggestions.'), const SizedBox(height: 12), FilledButton(onPressed: () => setState(() => tab = 0), child: const Text('Go to lessons'))]);
    final m = r['m'] as Map<String, dynamic>, pass = r['pass'] == true, f = Map<String, dynamic>.from(m['f']);
    final wpm = m['wpm'];
    final idx = lessons.indexWhere((x) => x.id == r['lid']);
    return pad([
      Text(r['lesson'], style: Theme.of(context).textTheme.titleLarge),
      Center(child: Text('${r['score']}/100', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: pass ? Colors.green : Colors.orange))),
      Center(child: Text('${pass ? '✅ Passed! ' : 'Target ${r['min']} to unlock the next lesson. '}+${r['xp']} XP${r['prev'] != null ? ' · previous attempt ${r['prev']}' : ''}', textAlign: TextAlign.center)),
      const SizedBox(height: 10),
      Text('${r['summary'] ?? ''}'),
      const SizedBox(height: 8),
      bar('Clarity', r['clarity']), bar('Structure', r['structure']), bar('Content', r['content']), bar('Delivery', r['delivery']),
      Row(children: [stat(wpm == null ? '–' : '$wpm', 'words/min'), stat('${m['tot']}', 'filler words'), stat('${m['w']}', 'words')]),
      if (wpm != null) Text(wpm < 110 ? 'A bit slow. Aim for 120-150 WPM.' : (wpm > 165 ? 'A bit fast. Slow down and pause.' : 'Good pace (ideal 120-150).')),
      if (f.isNotEmpty) Wrap(spacing: 6, children: f.entries.map((e) => Chip(label: Text('${e.key} ×${e.value}'))).toList()),
      list('👍 Strengths', L(r['strengths'])),
      list('⚠️ To improve', L(r['improvements'])),
      list('💡 Suggestions', L(r['suggestions'])),
      head('🏋️ Next drill'), Text('${r['drill'] ?? ''}'),
      head('✨ Stronger opening'), Text('${r['better_opening'] ?? ''}', style: const TextStyle(fontStyle: FontStyle.italic)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() { cur = lessons[idx]; tab = 1; }), child: const Text('Retry'))),
        if (pass && idx < lessons.length - 1) ...[const SizedBox(width: 8), Expanded(child: FilledButton(onPressed: () => setState(() { cur = lessons[idx + 1]; tx.clear(); secs = 0; tab = 1; }), child: const Text('Next lesson')))],
      ]),
    ]);
  }

  Widget progressPage() {
    final h = hist.length > 10 ? hist.sublist(hist.length - 10) : hist;
    final passed = lessons.where((x) => (done[x.id] ?? 0) >= x.min).length;
    return pad([
      Text('Progress', style: Theme.of(context).textTheme.headlineSmall),
      Row(children: [stat('🔥 $streak', 'day streak'), stat('⭐ $xp', 'XP · Lv ${xp ~/ 100 + 1}'), stat('$passed/9', 'lessons passed')]),
      head('Recent scores'),
      if (h.isEmpty) const Text('Your chart appears after your first evaluation.') else SizedBox(height: 120, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: h.map((e) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text('${e['score']}', style: const TextStyle(fontSize: 10)), Container(height: n(e['score']).toDouble() * 0.9, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(4)))])))).toList())),
      head('Badges'),
      Wrap(spacing: 6, children: [
        _badge('🎤 First speech', hist.isNotEmpty),
        _badge('🔥 3-day streak', streak >= 3),
        _badge('🥇 Score 90+', hist.any((e) => n(e['score']) >= 90)),
        _badge('🏆 Level 1 done', lessons.take(3).every((x) => (done[x.id] ?? 0) >= x.min)),
      ]),
      head('History'),
      ...hist.reversed.take(10).map((e) => ListTile(dense: true, title: Text('${e['lesson']}'), subtitle: Text('${e['date']}'), trailing: Text('${e['score']}', style: const TextStyle(fontWeight: FontWeight.bold)))),
    ]);
  }

  Widget _badge(String t, bool on) => Opacity(opacity: on ? 1 : .35, child: Chip(label: Text(t)));

  Widget profilePage() => pad([
        Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(controller: nameC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Your name'), onChanged: (v) { name = v; save(); }),
        const SizedBox(height: 12),
        TextField(controller: keyC, obscureText: true, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Gemini API key (AIza…)', helperText: 'Free key from aistudio.google.com. Stored only on this phone.'), onChanged: (v) { apiKey = v.trim(); save(); }),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Feedback language: '),
          DropdownButton<String>(value: aiLang, items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'si', child: Text('සිංහල'))], onChanged: (v) { setState(() => aiLang = v!); save(); }),
        ]),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () {
              setState(() { xp = 0; streak = 0; last = ''; done = {}; hist = []; view = null; });
              save();
            },
            child: const Text('Reset progress')),
      ]);

  @override
  Widget build(BuildContext c) {
    final pages = [learnPage(), practicePage(), feedbackPage(), progressPage(), profilePage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.school), label: 'Learn'),
          NavigationDestination(icon: Icon(Icons.mic), label: 'Practice'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Feedback'),
          NavigationDestination(icon: Icon(Icons.local_fire_department), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
