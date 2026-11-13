import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import 'checkout_sheet.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          if (cart.lines.isEmpty) return const Center(child: Text('Your cart is empty'));
          return Column(children: [
            Expanded(
              child: ListView(
                children: cart.lines.entries.map((e) {
                  final p = e.value['p'] as Map<String, dynamic>;
                  final q = e.value['qty'] as int;
                  return ListTile(
                    leading: SizedBox(width: 56, height: 56, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: netImg(firstImg(p)))),
                    title: Text(p['name'] ?? ''),
                    subtitle: Text(ugx((p['price'] as num) * q)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => cart.setQty(e.key, q - 1)),
                      Text('$q'),
                      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => cart.setQty(e.key, q + 1)),
                    ]),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Estimated item subtotal', style: TextStyle(fontSize: 16)),
                  Text(ugx(cart.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: gold)),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => _checkout(context), child: const Text('Checkout')),
              ]),
            ),
          ]);
        },
      );

  Future<void> _checkout(BuildContext context) async {
    final order = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const CheckoutSheet(),
    );
    if (!context.mounted || order == null) return;
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Order submitted'),
      content: Text('Order ID: ${order['id']}\nStatus: ${order['status']}\nItem total: ${ugx(order['total'] as num)}\n\nNo payment was collected. Delivery availability and cost are not yet confirmed.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
    ));
  }
}
