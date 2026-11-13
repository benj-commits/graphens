import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// One conversation per customer. Used by the customer (asAdmin=false) and the admin (asAdmin=true).
class ChatView extends StatefulWidget {
  final String customerId;
  final bool asAdmin;
  const ChatView({super.key, required this.customerId, required this.asAdmin, this.streamFactory, this.sendMessage});
  final Stream<List<Map<String, dynamic>>> Function(String customerId)? streamFactory;
  final Future<void> Function(String message)? sendMessage;
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ctrl = TextEditingController();
  late Stream<List<Map<String, dynamic>>> stream;
  bool sending = false;
  int streamGeneration = 0;

  Stream<List<Map<String, dynamic>>> _loadStream() => widget.streamFactory?.call(widget.customerId) ??
      db.from('messages').stream(primaryKey: ['id']).eq('customer_id', widget.customerId).order('created_at', ascending: false);

  @override
  void initState() {
    super.initState();
    stream = _loadStream();
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId || oldWidget.asAdmin != widget.asAdmin) {
      ctrl.clear();
    }
    if (oldWidget.customerId != widget.customerId || oldWidget.asAdmin != widget.asAdmin || oldWidget.streamFactory != widget.streamFactory) {
      streamGeneration++;
      stream = _loadStream();
    }
  }

  Future<void> send() async {
    final t = ctrl.text.trim();
    if (t.isEmpty || sending) return;
    final targetCustomer = widget.customerId;
    final targetAsAdmin = widget.asAdmin;
    setState(() => sending = true);
    try {
      if (widget.sendMessage != null) {
        await widget.sendMessage!(t);
      } else {
        await db.from('messages').insert({
          'customer_id': widget.customerId,
          'sender_id': db.auth.currentUser?.id ?? widget.customerId,
          'is_admin': widget.asAdmin,
          'body': t,
        });
      }
      if (mounted && widget.customerId == targetCustomer && widget.asAdmin == targetAsAdmin) ctrl.clear();
    } catch (_) {
      if (mounted && widget.customerId == targetCustomer && widget.asAdmin == targetAsAdmin) {
        snack(context, 'Could not confirm the message was sent. Check the chat before retrying.');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(streamGeneration),
            stream: stream,
            builder: (c, s) {
              if (s.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load chat. Please try again.'),
                TextButton(onPressed: () => setState(() { streamGeneration++; stream = _loadStream(); }), child: const Text('Retry')),
              ]));
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
              Expanded(child: TextField(controller: ctrl, enabled: !sending, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: sending ? 'Sending…' : 'Type a message'))),
              const SizedBox(width: 8),
              IconButton.filled(style: IconButton.styleFrom(backgroundColor: gold), onPressed: sending ? null : send, icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
            ]),
          ),
        ),
      ]);
}
