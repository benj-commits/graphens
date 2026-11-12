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
    final voucher = TextEditingController();
    String pay = 'MTN Request to Pay';
    String deliverySlot = deliverySlots.first;
    bool useLocation = false;
    bool locationNoticeShown = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Checkout', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone for delivery')),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Delivery address / area')),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Order note (optional)')),
              const SizedBox(height: 10),
              TextField(controller: voucher, decoration: const InputDecoration(labelText: 'Voucher code (optional)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: pay,
                items: const ['MTN Request to Pay', 'Airtel Request to Pay', 'Cash on delivery'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => set(() => pay = v ?? pay),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: deliverySlot,
                items: deliverySlots.map((slot) => DropdownMenuItem(value: slot, child: Text(slot))).toList(),
                onChanged: (v) => set(() => deliverySlot = v ?? deliverySlot),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(value: useLocation, onChanged: (v) async {
                    set(() => useLocation = v ?? false);
                    if (v == true && !locationNoticeShown) {
                      locationNoticeShown = true;
                      if (ctx.mounted) {
                        await requestLocationIfNeeded(context: ctx, showNotice: true);
                      }
                    }
                  }),
                  const Expanded(child: Text('Share my delivery location')),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Delivery fee is set by the admin and must be accepted by the customer before final confirmation.',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  if (phone.text.trim().isEmpty || address.text.trim().isEmpty) {
                    snack(ctx, 'Phone and address are required');
                    return;
                  }
                  try {
                    final discount = voucher.text.trim().toUpperCase() == 'GRAPHEN10' ? 0.1 : 0.0;
                    final subtotal = cart.total * (1 - discount);
                    final orderId = (DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');

                    await db.from('orders').insert({
                      'user_id': db.auth.currentUser!.id,
                      'customer_name': myName(),
                      'phone': phone.text.trim(),
                      'address': address.text.trim(),
                      'note': note.text.trim(),
                      'payment_method': pay,
                      'total': subtotal,
                      'delivery_fee': 0,
                      'delivery_fee_confirmed': false,
                      'delivery_fee_status': 'pending_customer_confirmation',
                      'status': 'pending',
                      'items': cart.lines.values
                          .map((l) => {'id': l['p']['id'], 'name': l['p']['name'], 'price': l['p']['price'], 'qty': l['qty']})
                          .toList(),
                    });
                    cart.clear();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Order sent', style: TextStyle(color: Colors.green)),
                          content: Text('Your order #${orderId} has been placed.\nThe admin will add the delivery fee and ask you to confirm it before final payment.\nDelivery slot: $deliverySlot\nPayment: $pay'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                          ],
                        ),
                      );
                    }
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
