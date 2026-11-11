import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String cat = 'All';
  String q = '';
  final stream = db.from('products').stream(primaryKey: ['id']).eq('active', true).order('created_at', ascending: false);

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Welcome back, ${myFirstName()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => setState(() => q = v.toLowerCase()),
                decoration: const InputDecoration(hintText: 'Search bags, cases, wallets', prefixIcon: Icon(Icons.search), isDense: true),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: ['All', ...categories]
                .map((c) => Padding(
                      padding: const EdgeInsets.all(6),
                      child: ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c)),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator(color: gold));
              final list = s.data!.where((p) => (cat == 'All' || p['category'] == cat) && (q.isEmpty || (p['name'] ?? '').toString().toLowerCase().contains(q))).toList();
              if (list.isEmpty) return const Center(child: Text('Nothing here yet'));
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, childAspectRatio: .72, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: list.length,
                itemBuilder: (_, i) => _Card(list[i]),
              );
            },
          ),
        ),
      ]);
}

class _Card extends StatelessWidget {
  final Map<String, dynamic> p;
  const _Card(this.p);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(p))),
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: SizedBox(width: double.infinity, child: netImg(firstImg(p)))),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(ugx(p['price'] ?? 0), style: const TextStyle(color: gold, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      );
}

class ProductDetail extends StatefulWidget {
  final Map<String, dynamic> p;
  const ProductDetail(this.p, {super.key});

  @override
  State<ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetail> {
  final comment = TextEditingController();
  int rating = 5;
  bool loading = false;
  Set<String> wishlist = {};

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  Future<void> _loadWishlist() async {
    final ids = await WishlistStorage.load();
    if (!mounted) return;
    setState(() => wishlist = ids);
  }

  Future<void> _saveReview() async {
    if (comment.text.trim().isEmpty) return;
    setState(() => loading = true);
    await ProductReviewStorage.submitReview(widget.p['id'], rating, comment.text.trim());
    comment.clear();
    if (!mounted) return;
    setState(() => loading = false);
    snack(context, 'Review submitted');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final imgs = (p['images'] ?? []) as List;
    final out = (p['stock'] ?? 1) <= 0;
    final productId = p['id'].toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(p['name'] ?? ''),
        actions: [
          IconButton(
            icon: Icon(wishlist.contains(productId) ? Icons.favorite : Icons.favorite_border),
            onPressed: () async {
              await WishlistStorage.toggle(productId);
              await _loadWishlist();
              snack(context, wishlist.contains(productId) ? 'Saved to wishlist' : 'Removed from wishlist');
            },
          ),
        ],
      ),
      body: ListView(children: [
        SizedBox(height: 340, child: imgs.isEmpty ? netImg(null) : PageView(children: imgs.map((u) => netImg(u as String)).toList())),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(ugx(p['price'] ?? 0), style: const TextStyle(fontSize: 20, color: gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(out ? 'Out of stock' : 'In stock', style: TextStyle(color: out ? Colors.red : Colors.green)),
            const SizedBox(height: 12),
            Text(p['description'] ?? ''),
            const SizedBox(height: 16),
            FutureBuilder<double>(
              future: ProductReviewStorage.averageForProduct(productId),
              builder: (context, snapshot) {
                final avg = snapshot.data ?? 0;
                final label = avg > 0 ? '${avg.toStringAsFixed(1)} / 5' : 'No ratings yet';
                return Text('Average rating: $label', style: const TextStyle(fontWeight: FontWeight.w600));
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: out ? null : () {
                cart.add(p);
                snack(context, 'Added to cart');
              },
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Add to cart'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const Text('Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              DropdownButton<int>(value: rating, items: [5, 4, 3, 2, 1].map((i) => DropdownMenuItem(value: i, child: Text('$i ★'))).toList(), onChanged: (v) => setState(() => rating = v ?? 5)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: comment, decoration: const InputDecoration(hintText: 'Write a review'))),
              IconButton(onPressed: loading ? null : _saveReview, icon: const Icon(Icons.send, color: gold)),
            ]),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: ProductReviewStorage.loadForProduct(productId),
              builder: (context, snapshot) {
                final reviews = snapshot.data ?? const [];
                if (reviews.isEmpty) return const Text('No reviews yet. Be the first to review this item.');
                return Column(
                  children: reviews.map((review) {
                    final r = ((review['rating'] as int?) ?? 0);
                    return Card(
                      child: ListTile(
                        title: Text('${review['name'] ?? 'Customer'}  ${'★' * r}'),
                        subtitle: Text(review['comment'] ?? ''),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
