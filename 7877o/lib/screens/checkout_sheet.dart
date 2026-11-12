import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

/// Request identifiers are persisted before submission so an interrupted
/// request can be retried without creating a second order.
String newCheckoutRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String checkoutDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({super.key});

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController phone;
  final address = TextEditingController();
  final note = TextEditingController();
  DateTime? preferredDate;
  bool consent = false;
  bool busy = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    phone = TextEditingController(text: db.auth.currentUser?.userMetadata?['phone']?.toString() ?? '');
  }

  @override
  void dispose() {
    phone.dispose();
    address.dispose();
    note.dispose();
    super.dispose();
  }

  String? requiredText(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> submit() async {
    if (busy || !formKey.currentState!.validate()) return;
    if (!consent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to share your delivery details.')));
      return;
    }
    final user = db.auth.currentUser;
    if (user == null || cart.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in and add items to your cart first.')));
      return;
    }
    setState(() { busy = true; failed = false; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'checkout_request_v1_${user.id}';
      var requestId = prefs.getString(key);
      if (requestId == null) {
        requestId = newCheckoutRequestId();
        if (!await prefs.setString(key, requestId)) {
          throw StateError('Could not save checkout request');
        }
      }
      final ids = cart.lines.keys.toList()..sort();
      final items = ids.map((id) => <String, dynamic>{'id': id, 'qty': cart.lines[id]!['qty']}).toList();
      final result = await db.rpc('place_checkout_order_v1', params: {
        'p_request_id': requestId,
        'p_phone': phone.text.trim(),
        'p_address': address.text.trim(),
        'p_note': note.text.trim(),
        'p_preferred_date': preferredDate == null ? null : checkoutDate(preferredDate!),
        'p_items': items,
      });
      final order = Map<String, dynamic>.from(result as Map);
      if (order['id'] == null || order['status'] == null || order['total'] is! num) {
        throw StateError('Incomplete order response');
      }
      // If local cleanup fails, retain the cart and request key: retry is safe.
      if (!await prefs.remove(key)) throw StateError('Could not clear checkout request');
      cart.clear();
      if (mounted) Navigator.of(context).pop(order);
    } catch (_) {
      if (mounted) setState(() { busy = false; failed = true; });
    }
  }

  Future<void> resetAttempt() async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Start a different order?'),
      content: const Text('First check My Orders. Your previous request may have succeeded even if the response was lost. Starting again could create a duplicate order.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep retry')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Start a new attempt')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    final user = db.auth.currentUser;
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove('checkout_request_v1_${user.id}')) throw StateError('Could not clear request');
      if (mounted) setState(() => failed = false);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reset this attempt. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Checkout', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextFormField(controller: phone, enabled: !busy, maxLength: 80, keyboardType: TextInputType.phone, validator: requiredText, decoration: const InputDecoration(labelText: 'Phone for delivery')),
        TextFormField(controller: address, enabled: !busy, maxLength: 500, validator: requiredText, decoration: const InputDecoration(labelText: 'Delivery address / area')),
        TextFormField(controller: note, enabled: !busy, maxLength: 1000, decoration: const InputDecoration(labelText: 'Order note (optional)')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: busy ? null : () async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final picked = await showDatePicker(context: context, initialDate: preferredDate != null && !preferredDate!.isBefore(today) ? preferredDate! : today, firstDate: today, lastDate: today.add(const Duration(days: 180)));
          if (picked != null && mounted) setState(() => preferredDate = picked);
        }, child: Text(preferredDate == null ? 'Choose preferred delivery date (optional)' : 'Preferred date: ${checkoutDate(preferredDate!)}')),
        if (preferredDate != null) TextButton(onPressed: busy ? null : () => setState(() => preferredDate = null), child: const Text('Clear date')),
        const Text('The date is a preference, not a confirmed delivery booking. If Faras is available, the Graphen team can arrange delivery separately after confirming the fee with you. No Faras booking or quote is made here.'),
        const SizedBox(height: 10),
        const Text('Cash on delivery requested. No payment is collected here; mobile money is not available in this checkout.'),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: consent, onChanged: busy ? null : (v) => setState(() => consent = v ?? false), title: const Text('I agree to share my phone, address and order details with Graphen to fulfil this order.')),
        const Text('No device location is collected or shared.'),
        if (failed) ...[
          const SizedBox(height: 12),
          const Text('We could not confirm the result. Check My Orders before placing another order. Retry with the same details to avoid duplicates. Checkout requires the latest database migration.', style: TextStyle(color: Colors.red)),
          TextButton(onPressed: busy ? null : resetAttempt, child: const Text('Start a different order')),
        ],
        const SizedBox(height: 12),
        ElevatedButton(onPressed: busy ? null : submit, child: Text(busy ? 'Submitting…' : 'Place order')),
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Close')),
      ]))),
    )),
  );
}
