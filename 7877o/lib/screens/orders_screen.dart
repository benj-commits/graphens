import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

typedef OrdersStreamFactory = Stream<List<Map<String, dynamic>>> Function();
typedef DeliveryFeeResponse = Future<void> Function(String orderId, int revision, bool accept);

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.streamFactory, this.respond});
  final OrdersStreamFactory? streamFactory;
  final DeliveryFeeResponse? respond;
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Stream<List<Map<String, dynamic>>> orders;
  final Set<String> responding = {};
  int generation = 0;
  Stream<List<Map<String, dynamic>>> loadOrders() {
    if (widget.streamFactory != null) return widget.streamFactory!();
    final user = db.auth.currentUser;
    if (user == null) return Stream.error(StateError('Sign in to view orders'));
    return db.from('orders').stream(primaryKey: ['id']).eq('user_id', user.id).order('created_at', ascending: false);
  }
  @override
  void initState() { super.initState(); orders = loadOrders(); }
  void refresh() { setState(() { generation++; orders = loadOrders(); }); }
  Future<void> respondToQuote(String id, int revision, bool accept) async {
    if (responding.contains(id)) return;
    setState(() => responding.add(id));
    try {
      if (widget.respond != null) {
        await widget.respond!(id, revision, accept);
      } else {
        await db.rpc('respond_delivery_fee_v1', params: {'p_order_id': id, 'p_revision': revision, 'p_accept': accept});
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not confirm your response. The quote may have changed or the connection may have failed. Refresh and check the latest quote before trying again.')));
    } finally {
      if (mounted) setState(() { responding.remove(id); generation++; orders = loadOrders(); });
    }
  }
  num? amount(dynamic value) {
    final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: responding.isEmpty ? refresh : null, icon: const Icon(Icons.refresh), label: const Text('Refresh orders'))),
    Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(key: ValueKey(generation), stream: orders, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Could not load orders. Please try again.'), TextButton(onPressed: refresh, child: const Text('Retry'))]));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: gold));
      if (snapshot.data!.isEmpty) return const Center(child: Text('No orders yet'));
      return ListView(children: snapshot.data!.map(orderCard).toList());
    })),
  ]);
  Widget orderCard(Map<String, dynamic> order) {
    final id = order['id']?.toString() ?? '';
    final subtotal = amount(order['total']);
    final fee = amount(order['delivery_fee']);
    final revision = order['delivery_fee_revision'];
    final feeStatus = order['delivery_fee_status']?.toString();
    final items = (order['items'] is List ? order['items'] as List : const []).whereType<Map>().map((i) => '${i['qty']} x ${i['name']}').join(', ');
    final status = (order['status'] ?? 'pending').toString();
    final busy = responding.contains(id);
    String feeLabel;
    switch (feeStatus) {
      case 'awaiting_quote': feeLabel = 'Delivery fee: awaiting quote from Graphen'; break;
      case 'offered': feeLabel = 'Delivery fee: offered — your response is needed'; break;
      case 'accepted': feeLabel = 'Delivery fee: accepted'; break;
      case 'declined': feeLabel = 'Delivery fee: declined'; break;
      default: feeLabel = 'Delivery fee status unavailable';
    }
    final hasQuote = fee != null && (feeStatus == 'offered' || feeStatus == 'accepted' || feeStatus == 'declined');
    final canRespond = feeStatus == 'offered' && hasQuote && subtotal != null && revision is int && id.isNotEmpty;
    return Card(margin: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Order $id', style: Theme.of(context).textTheme.titleMedium), Text('Order status: $status'), const SizedBox(height: 6),
      if (items.isNotEmpty) Text(items), Text('Item subtotal: ${subtotal == null ? 'Unavailable' : ugx(subtotal)}'), const SizedBox(height: 4),
      Text(feeLabel), if (hasQuote) Text('Quoted delivery fee: ${ugx(fee!)}'),
      if (hasQuote && subtotal != null) Text('${feeStatus == 'accepted' ? 'Grand total' : 'Total if delivery fee accepted'}: ${ugx(subtotal + fee!)}'),
      if (feeStatus == 'awaiting_quote') const Text('The total is not yet available. Approve the fee before fulfilment.'),
      if (feeStatus == 'offered' && !canRespond) const Text('Quote details are incomplete. Refresh or contact Graphen.'),
      if (canRespond) Wrap(spacing: 8, children: [ElevatedButton(onPressed: busy ? null : () => respondToQuote(id, revision, true), child: Text(busy ? 'Sending response…' : 'Accept delivery fee')), OutlinedButton(onPressed: busy ? null : () => respondToQuote(id, revision, false), child: const Text('Decline delivery fee'))]),
      const SizedBox(height: 4), Text('Payment method requested: ${order['payment_method'] ?? 'Not recorded'}', style: const TextStyle(fontSize: 12)),
      const Text('Payment status is not available here.', style: TextStyle(fontSize: 12)),
      if (order['preferred_delivery_date'] != null) Text('Preferred delivery date: ${order['preferred_delivery_date']} (not confirmed)', style: const TextStyle(fontSize: 12)),
    ])));
  }
}
