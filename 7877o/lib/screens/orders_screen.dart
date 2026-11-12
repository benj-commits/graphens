import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.from('orders').stream(primaryKey: ['id']).eq('user_id', db.auth.currentUser!.id).order('created_at', ascending: false),
        builder: (c, s) {
          if (s.hasError) return const Center(child: Text('Could not load orders. Please try again later.'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: gold));
          if (s.data!.isEmpty) return const Center(child: Text('No orders yet'));
          return ListView(
            children: s.data!.map((o) {
              final items = (o['items'] as List).map((i) => '${i['qty']} x ${i['name']}').join(', ');
              final status = (o['status'] ?? 'pending').toString();
              final isConfirmed = status == 'confirmed' || status == 'processing' || status == 'delivered';
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  title: Text('Order ${o['id']}\nItem total: ${ugx(o['total'] as num)}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(items),
                      const SizedBox(height: 4),
                      Text('Payment method requested: ${o['payment_method'] ?? 'Not recorded'}', style: const TextStyle(fontSize: 12)),
                      const Text('Payment status is not available here.', style: TextStyle(fontSize: 12)),
                      if (o['preferred_delivery_date'] != null)
                        Text('Preferred delivery date: ${o['preferred_delivery_date']} (not confirmed)', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  trailing: Chip(
                    label: Text(status),
                    backgroundColor: isConfirmed ? Colors.green.shade100 : Colors.orange.shade100,
                    labelStyle: TextStyle(color: isConfirmed ? Colors.green.shade900 : Colors.orange.shade900),
                  ),
                ),
              );
            }).toList(),
          );
        },
      );
}
