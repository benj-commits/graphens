import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// One conversation per customer. Used by the customer (asAdmin=false) and the admin (asAdmin=true).
class ChatView extends StatefulWidget {
  final String customerId;
  final bool asAdmin;
  const ChatView({super.key, required this.customerId, required this.asAdmin});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ctrl = TextEditingController();
  late final stream = db.from('messages').stream(primaryKey: ['id']).eq('customer_id', widget.customerId).order('created_at', ascending: false);

  Future<void> send() async {
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    ctrl.clear();
    try {
      await db.from('messages').insert({
        'customer_id': widget.customerId,
        'sender_id': db.auth.currentUser?.id ?? widget.customerId,
        'is_admin': widget.asAdmin,
        'body': t,
      });
    } catch (e) {
      if (mounted) snack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator(color: gold));
              final msgs = s.data!;
              if (msgs.isEmpty) return const Center(child: Text('Say hello'));
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final mine = (m['is_admin'] == true) == widget.asAdmin;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: const BoxConstraints(maxWidth: 300),
                      decoration: BoxDecoration(color: mine ? ink : Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Text(m['body'] ?? '', style: TextStyle(color: mine ? Colors.white : ink)),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: ctrl, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Type a message'))),
              const SizedBox(width: 8),
              IconButton.filled(style: IconButton.styleFrom(backgroundColor: gold), onPressed: send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]);
}
