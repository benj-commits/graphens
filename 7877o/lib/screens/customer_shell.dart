import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'wishlist_screen.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int i = 0;

  @override
  Widget build(BuildContext context) {
    final customerId = db.auth.currentUser?.id ?? 'guest-user';
    final pages = [
      const ShopScreen(),
      const WishlistScreen(),
      const CartScreen(),
      const OrdersScreen(),
      ChatView(customerId: customerId, asAdmin: false),
    ];
    const titles = ['Shop', 'Wishlist', 'My Cart', 'My Orders', 'Chat with Graphen'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[i]),
        actions: [
          IconButton(
            icon: const Icon(Icons.support_agent_outlined),
            tooltip: 'WhatsApp support',
            onPressed: () async {
              await openWhatsApp(phone: '+256779572987');
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
        ],
      ),
      body: IndexedStack(index: i, children: pages),
      bottomNavigationBar: ListenableBuilder(
        listenable: cart,
        builder: (_, __) => NavigationBar(
          selectedIndex: i,
          indicatorColor: gold.withValues(alpha: .3),
          onDestinationSelected: (v) => setState(() => i = v),
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
