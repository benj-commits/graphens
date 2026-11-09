import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.from('projects').stream(primaryKey: ['id']).eq('active', true).order('created_at', ascending: false),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: gold));
          if (s.data!.isEmpty) return const Center(child: Text('No projects yet'));
          return ListView(
            padding: const EdgeInsets.all(12),
            children: s.data!
                .map((p) => InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectDetail(p))),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(height: 180, width: double.infinity, child: netImg(firstImg(p))),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p['title'] ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              Text('${p['category'] ?? ''}  -  from ${ugx(p['price_from'] ?? 0)}', style: const TextStyle(color: gold)),
                            ]),
                          ),
                        ]),
                      ),
                    ))
                .toList(),
          );
        },
      );
}

class ProjectDetail extends StatefulWidget {
  final Map<String, dynamic> p;
  const ProjectDetail(this.p, {super.key});
  @override
  State<ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends State<ProjectDetail> {
  final comment = TextEditingController();
  int rating = 5;

  Future<void> enquire() async {
    await db.from('messages').insert({
      'customer_id': db.auth.currentUser!.id,
      'sender_id': db.auth.currentUser!.id,
      'is_admin': false,
      'body': 'Hi, I am interested in the project "${widget.p['title']}". Please share more details.',
    });
    if (mounted) snack(context, 'Sent! Open the Chat tab to continue.');
  }

  Future<void> sendFeedback() async {
    if (comment.text.trim().isEmpty) return;
    await db.from('feedback').insert({
      'project_id': widget.p['id'],
      'user_id': db.auth.currentUser!.id,
      'customer_name': myName(),
      'rating': rating,
      'comment': comment.text.trim(),
    });
    comment.clear();
    if (mounted) snack(context, 'Thanks for your feedback');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final imgs = (p['images'] ?? []) as List;
    return Scaffold(
      appBar: AppBar(title: Text(p['title'] ?? '')),
      body: ListView(children: [
        SizedBox(height: 300, child: imgs.isEmpty ? netImg(null) : PageView(children: imgs.map((u) => netImg(u as String)).toList())),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('From ${ugx(p['price_from'] ?? 0)}', style: const TextStyle(fontSize: 18, color: gold, fontWeight: FontWeight.w800)),
            if ((p['status'] ?? '').toString().isNotEmpty) Text('Status: ${p['status']}'),
            const SizedBox(height: 10),
            Text(p['description'] ?? ''),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: enquire, icon: const Icon(Icons.chat), label: const Text('Enquire about this project')),
            const Divider(height: 36),
            const Text('Feedback', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              DropdownButton<int>(value: rating, items: [5, 4, 3, 2, 1].map((i) => DropdownMenuItem(value: i, child: Text('$i \u2605'))).toList(), onChanged: (v) => setState(() => rating = v!)),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: comment, decoration: const InputDecoration(hintText: 'Leave a comment'))),
              IconButton(onPressed: sendFeedback, icon: const Icon(Icons.send, color: gold)),
            ]),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: db.from('feedback').stream(primaryKey: ['id']).eq('project_id', p['id']).order('created_at', ascending: false),
              builder: (c, s) => Column(
                children: (s.data ?? [])
                    .map((f) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${f['customer_name'] ?? 'Customer'}  ${'\u2605' * ((f['rating'] ?? 0) as int)}'),
                          subtitle: Text(f['comment'] ?? ''),
                        ))
                    .toList(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
