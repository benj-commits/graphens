import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'shop_screen.dart';
import 'projects_screen.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';
import 'chat_view.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});
  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const ShopScreen(),
      const ProjectsScreen(),
      const CartScreen(),
      const OrdersScreen(),
      ChatView(customerId: db.auth.currentUser!.id, asAdmin: false),
    ];
    const titles = ['Shop', 'Our Projects', 'My Cart', 'My Orders', 'Chat with Graphen'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[i]), actions: [
        IconButton(icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
      ]),
      body: IndexedStack(index: i, children: pages),
      bottomNavigationBar: ListenableBuilder(
        listenable: cart,
        builder: (_, __) => NavigationBar(
          selectedIndex: i,
          indicatorColor: gold.withValues(alpha: .3),
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
            const NavigationDestination(icon: Icon(Icons.collections_outlined), label: 'Projects'),
            NavigationDestination(icon: Badge(isLabelVisible: cart.count > 0, label: Text('${cart.count}'), child: const Icon(Icons.shopping_bag_outlined)), label: 'Cart'),
            const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          ],
        ),
      ),
    );
  }
}
