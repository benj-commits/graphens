import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../theme.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  Set<String> wishlisted = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await WishlistStorage.load();
    if (!mounted) return;
    setState(() => wishlisted = ids);
  }

  @override
  Widget build(BuildContext context) {
    if (wishlisted.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Your wishlist is empty. Save products you love from the shop.'),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.from('products').select().eq('active', true).then((r) => r.cast<Map<String, dynamic>>().where((p) => wishlisted.contains(p['id'])).toList()),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: gold));
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No saved products found.'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: items.map((p) {
            final id = p['id'].toString();
            return Card(
              child: ListTile(
                leading: SizedBox(width: 60, height: 60, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: netImg(firstImg(p)))),
                title: Text(p['name'] ?? ''),
                subtitle: Text(ugx(p['price'] ?? 0)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart),
                      onPressed: () {
                        cart.add(p);
                        snack(context, 'Added to cart');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ids = await WishlistStorage.load();
                        ids.remove(id);
                        await WishlistStorage.save(ids);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
