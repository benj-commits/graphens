import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

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
                  const Text('Total', style: TextStyle(fontSize: 16)),
                  Text(ugx(cart.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: gold)),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => _checkout(context), child: const Text('Checkout')),
              ]),
            ),
          ]);
        },
      );

  void _checkout(BuildContext context) {
    final phone = TextEditingController(text: db.auth.currentUser?.userMetadata?['phone']?.toString() ?? '');
    final address = TextEditingController();
    final note = TextEditingController();
    String pay = 'Mobile Money on delivery';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone for delivery')),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Delivery address / area')),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: pay,
                items: const ['Mobile Money on delivery', 'Cash on delivery', 'Pay at pickup'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => set(() => pay = v!),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  if (phone.text.trim().isEmpty || address.text.trim().isEmpty) {
                    snack(ctx, 'Phone and address are required');
                    return;
                  }
                  try {
                    await db.from('orders').insert({
                      'user_id': db.auth.currentUser!.id,
                      'customer_name': myName(),
                      'phone': phone.text.trim(),
                      'address': address.text.trim(),
                      'note': note.text.trim(),
                      'payment_method': pay,
                      'total': cart.total,
                      'items': cart.lines.values
                          .map((l) => {'id': l['p']['id'], 'name': l['p']['name'], 'price': l['p']['price'], 'qty': l['qty']})
                          .toList(),
                    });
                    cart.clear();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) snack(context, 'Order placed! We will contact you shortly.');
                  } catch (e) {
                    if (ctx.mounted) snack(ctx, e.toString());
                  }
                },
                child: const Text('Place order'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
