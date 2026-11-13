import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';
import 'shop_screen.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';
import 'chat_view.dart';
import 'wishlist_screen.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int i = 0;
  final visited = <int>{0};

  void _selectPage(int index) {
    setState(() { i = index; visited.add(index); });
  }

  void _showSupport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SupportSheet(
        initialTopic: i,
        onChat: () {
          Navigator.pop(sheetContext);
          _selectPage(4);
        },
        onWhatsApp: (uri) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              messenger.showSnackBar(const SnackBar(content: Text('Could not open WhatsApp. Contact +256 779 572 987 instead.')));
            }
          } catch (_) {
            messenger.showSnackBar(const SnackBar(content: Text('Could not open WhatsApp. Contact +256 779 572 987 instead.')));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerId = db.auth.currentUser?.id ?? 'guest-user';
    final pages = [
      const ShopScreen(),
      WishlistScreen(active: i == 1),
      const CartScreen(),
      const OrdersScreen(),
      ChatView(customerId: customerId, asAdmin: false),
    ];
    const titles = ['Shop', 'Wishlist', 'My Cart', 'My Orders', 'Chat with Graphen'];

    return Scaffold(
      appBar: AppBar(
        title: i == 0 ? const Text('Graphens', style: TextStyle(fontFamily: 'cursive', fontSize: 27, fontWeight: FontWeight.w700)) : Text(titles[i]),
        actions: [
          IconButton(
            icon: const Icon(Icons.support_agent_outlined),
            tooltip: 'Customer support',
            onPressed: _showSupport,
          ),
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
        ],
      ),
      // Keep visited tabs alive, but defer their streams and queries until opened.
      body: IndexedStack(index: i, children: [
        for (var index = 0; index < pages.length; index++)
          if (visited.contains(index)) pages[index] else const SizedBox.shrink(),
      ]),
      bottomNavigationBar: ListenableBuilder(
        listenable: cart,
        builder: (_, __) => NavigationBar(
          selectedIndex: i,
          indicatorColor: gold.withValues(alpha: .3),
          onDestinationSelected: _selectPage,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
            const NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Wishlist'),
            NavigationDestination(
              icon: Badge(isLabelVisible: cart.count > 0, label: Text('${cart.count}'), child: const Icon(Icons.shopping_bag_outlined)),
              label: 'Cart',
            ),
            const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          ],
        ),
      ),
    );
  }
}

/// Support drafts contain only a topic, never account or order information.
const supportTopics = ['Product question', 'Saved items', 'Cart or checkout', 'Order question', 'Something else'];

Uri supportWhatsAppUri(String topic) => Uri.https('wa.me', '/256779572987', {
      'text': 'Hello Graphen Bags, I need help with: $topic.',
    });

class SupportSheet extends StatefulWidget {
  const SupportSheet({super.key, required this.initialTopic, required this.onChat, required this.onWhatsApp});

  final int initialTopic;
  final VoidCallback onChat;
  final Future<void> Function(Uri) onWhatsApp;

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  late String topic = supportTopics[widget.initialTopic.clamp(0, supportTopics.length - 1)];
  bool opening = false;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('How can we help?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: ink, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Choose a topic and contact Graphen Bags. For order questions, have your order reference ready.'),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: topic,
              decoration: const InputDecoration(labelText: 'What do you need help with?'),
              items: supportTopics.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: opening ? null : (value) { if (value != null) setState(() => topic = value); },
            ),
            const SizedBox(height: 16),
            Text('WhatsApp draft: Hello Graphen Bags, I need help with: $topic.', style: const TextStyle(color: ink)),
            const SizedBox(height: 8),
            const Text('You can review and edit the message in WhatsApp. No account or order details are included automatically.'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: opening ? null : () async {
                setState(() => opening = true);
                try {
                  await widget.onWhatsApp(supportWhatsAppUri(topic));
                } finally {
                  if (mounted) setState(() => opening = false);
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Continue to WhatsApp'),
            ),
            TextButton.icon(onPressed: widget.onChat, icon: const Icon(Icons.chat_bubble_outline), label: const Text('Use in-app chat instead')),
            const Text('WhatsApp: +256 779 572 987', textAlign: TextAlign.center),
          ]),
        ),
      );
}
