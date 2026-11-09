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
          child: TextField(
            onChanged: (v) => setState(() => q = v.toLowerCase()),
            decoration: const InputDecoration(hintText: 'Search bags, cases, wallets', prefixIcon: Icon(Icons.search), isDense: true),
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

class ProductDetail extends StatelessWidget {
  final Map<String, dynamic> p;
  const ProductDetail(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    final imgs = (p['images'] ?? []) as List;
    final out = (p['stock'] ?? 1) <= 0;
    return Scaffold(
      appBar: AppBar(title: Text(p['name'] ?? '')),
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: out ? null : () {
                cart.add(p);
                snack(context, 'Added to cart');
              },
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Add to cart'),
            ),
          ]),
        ),
      ]),
    );
  }
}
