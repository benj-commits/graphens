import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

typedef WishlistIdsLoader = Future<Set<String>> Function();
typedef WishlistIdsSaver = Future<void> Function(Set<String> ids);
typedef WishlistProductsLoader = Future<List<Map<String, dynamic>>> Function();

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key, this.active = true, this.loadIds, this.saveIds, this.loadProducts});

  final bool active;
  // Optional dependencies let the loading and retry behaviour be tested without a network.
  final WishlistIdsLoader? loadIds;
  final WishlistIdsSaver? saveIds;
  final WishlistProductsLoader? loadProducts;

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  Set<String> wishlisted = {};
  List<Map<String, dynamic>> items = [];
  bool loading = false;
  bool failed = false;
  bool removing = false;
  int generation = 0;

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    if (widget.loadProducts != null) return widget.loadProducts!();
    final result = await db.from('products').select().eq('active', true);
    return result.cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant WishlistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _load() async {
    final current = ++generation;
    setState(() { loading = true; failed = false; });
    try {
      final ids = await (widget.loadIds ?? WishlistStorage.load)();
      final products = ids.isEmpty ? <Map<String, dynamic>>[] : await _loadProducts();
      if (!mounted || current != generation) return;
      setState(() {
        wishlisted = ids;
        items = products.where((p) => ids.contains(p['id'].toString())).toList();
        loading = false;
      });
    } catch (_) {
      if (!mounted || current != generation) return;
      setState(() { loading = false; failed = true; });
    }
  }

  Future<void> _remove(String id) async {
    if (removing) return;
    setState(() => removing = true);
    try {
      // Re-read before writing to avoid using an older view of the wishlist.
      final ids = await (widget.loadIds ?? WishlistStorage.load)();
      ids.remove(id);
      await (widget.saveIds ?? WishlistStorage.save)(ids);
      if (!mounted) return;
      // Reload after saving: a tab refresh may have raced with the write.
      await _load();
    } catch (_) {
      if (mounted) snack(context, 'Could not update wishlist. Please try again.');
    } finally {
      if (mounted) setState(() => removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: gold));
    if (failed) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Could not load wishlist. Please try again.'),
      TextButton(onPressed: _load, child: const Text('Retry')),
    ]));
    if (wishlisted.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Your wishlist is empty. Save products you love from the shop.'),
      ));
    }
    if (items.isEmpty) return const Center(child: Text('No saved products found.'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final p = items[index];
        final id = p['id'].toString();
        return Card(child: ListTile(
          leading: SizedBox(width: 60, height: 60, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: netImg(firstImg(p)))),
          title: Text(p['name'] ?? ''),
          subtitle: Text(ugx(p['price'] ?? 0)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.add_shopping_cart), onPressed: () {
              cart.add(p);
              snack(context, 'Added to cart');
            }),
            IconButton(tooltip: removing ? 'Updating wishlist' : 'Remove from wishlist',
              icon: removing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline),
              onPressed: removing ? null : () => _remove(id)),
          ]),
        ));
      },
    );
  }
}
