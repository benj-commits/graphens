import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'theme.dart';

SupabaseClient get db => Supabase.instance.client;

const categories = ['Lady Bags', 'Handbags', 'Cases', 'Wallets & More', 'Other'];
const orderStatuses = ['pending', 'confirmed', 'processing', 'delivered', 'cancelled'];
const deliverySlots = [
  'Today • 10:00 AM',
  'Today • 2:00 PM',
  'Tomorrow • 9:30 AM',
  'Tomorrow • 1:30 PM',
  'Saturday • 11:00 AM',
];
const providerOptions = ['Faras', 'Uber', 'SafeBoda'];
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
String myFirstName() {
  final full = myName().trim();
  if (full.isEmpty) return 'there';
  return full.split(RegExp(r'\s+')).first;
}

void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: m.toLowerCase().contains('success') || m.toLowerCase().contains('confirmed') ? Colors.green.shade700 : null,
      ));

Future<void> openWhatsApp({required String phone}) async {
  final normalized = phone.replaceAll(RegExp(r'\D'), '');
  final phoneNumber = normalized.startsWith('0') ? '256${normalized.substring(1)}' : normalized;
  final url = 'https://wa.me/$phoneNumber';
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<Position?> requestLocationIfNeeded({required BuildContext context, bool showNotice = true}) async {
  final status = await Permission.location.request();
  if (status.isGranted) {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('graphen_last_location', '${pos.latitude},${pos.longitude}');
      return pos;
    } catch (_) {
      if (context.mounted) snack(context, 'Location access was granted but location could not be read.');
    }
  } else {
    if (showNotice && context.mounted) {
      snack(context, 'Location is needed for delivery and tracking, but can be turned back on in settings.');
    }
  }
  return null;
}

Future<LocalAuthentication> getBiometricAuth() async => LocalAuthentication();

Future<bool> tryBiometricAuth() async {
  final auth = LocalAuthentication();
  try {
    return await auth.canCheckBiometrics &&
        await auth.authenticate(
          localizedReason: 'Verify it is you to continue',
          options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
        );
  } catch (_) {
    return false;
  }
}

class ProductReviewStorage {
  static const key = 'graphen_product_reviews';

  static Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final map = <String, List<Map<String, dynamic>>>{};
      decoded.forEach((productId, value) {
        if (value is List) {
          map[productId] = value
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      });
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> loadForProduct(String productId) async {
    final all = await loadAll();
    return all[productId] ?? const [];
  }

  static Future<void> submitReview(String productId, int rating, String comment) async {
    final all = await loadAll();
    final list = [...(all[productId] ?? const []), {
      'rating': rating,
      'comment': comment.trim(),
      'name': myName(),
      'created_at': DateTime.now().toIso8601String(),
    }];
    all[productId] = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(all));
  }

  static Future<double> averageForProduct(String productId) async {
    final reviews = await loadForProduct(productId);
    if (reviews.isEmpty) return 0;
    final total = reviews.fold<int>(0, (sum, item) => sum + ((item['rating'] as int?) ?? 0));
    return total / reviews.length;
  }
}

class WishlistStorage {
  static const key = 'graphen_wishlist';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? []).toSet();
  }

  static Future<void> save(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, ids.toList());
  }

  static Future<void> toggle(String productId) async {
    final ids = await load();
    if (ids.contains(productId)) {
      ids.remove(productId);
    } else {
      ids.add(productId);
    }
    await save(ids);
  }
}

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
