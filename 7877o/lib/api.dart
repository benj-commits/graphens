import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

SupabaseClient get db => Supabase.instance.client;

const categories = ['Lady Bags', 'Handbags', 'Cases', 'Wallets & More', 'Other'];
const orderStatuses = ['pending', 'confirmed', 'processing', 'delivered', 'cancelled'];

String ugx(num n) => 'UGX ${NumberFormat('#,###').format(n)}';

String? firstImg(Map m) {
  final l = (m['images'] ?? []) as List;
  return l.isEmpty ? null : l.first as String;
}

Widget netImg(String? url, {BoxFit fit = BoxFit.cover}) {
  final ph = Container(color: const Color(0xFFEEE6D8), child: const Center(child: Icon(Icons.shopping_bag_outlined, color: gold)));
  if (url == null || url.isEmpty) return ph;
  return Image.network(url, fit: fit, errorBuilder: (_, __, ___) => ph);
}

String myName() => (db.auth.currentUser?.userMetadata?['full_name'] ?? 'Customer').toString();

void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class Cart extends ChangeNotifier {
  final lines = <String, Map<String, dynamic>>{};
  void add(Map<String, dynamic> p) {
    final id = p['id'] as String;
    if (lines.containsKey(id)) {
      lines[id]!['qty'] = (lines[id]!['qty'] as int) + 1;
    } else {
      lines[id] = {'p': p, 'qty': 1};
    }
    notifyListeners();
  }

  void setQty(String id, int q) {
    if (q <= 0) {
      lines.remove(id);
    } else {
      lines[id]!['qty'] = q;
    }
    notifyListeners();
  }

  num get total => lines.values.fold<num>(0, (s, l) => s + (l['p']['price'] as num) * (l['qty'] as int));
  int get count => lines.values.fold<int>(0, (s, l) => s + (l['qty'] as int));
  void clear() {
    lines.clear();
    notifyListeners();
  }
}

final cart = Cart();
