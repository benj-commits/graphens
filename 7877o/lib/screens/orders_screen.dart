import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.from('orders').stream(primaryKey: ['id']).eq('user_id', db.auth.currentUser!.id).order('created_at', ascending: false),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator(color: gold));
          if (s.data!.isEmpty) return const Center(child: Text('No orders yet'));
          return ListView(
            children: s.data!.map((o) {
              final items = (o['items'] as List).map((i) => '${i['qty']} x ${i['name']}').join(', ');
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  title: Text('Order #${(o['id'] as String).substring(0, 6).toUpperCase()}  -  ${ugx(o['total'])}'),
                  subtitle: Text(items),
                  trailing: Chip(label: Text(o['status'])),
                ),
              );
            }).toList(),
          );
        },
      );
}
