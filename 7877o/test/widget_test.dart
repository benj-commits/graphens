import 'package:flutter_test/flutter_test.dart';
import 'package:graphen_bags/api.dart';

void main() {
  test('cart tracks item quantity and total', () {
    final cart = Cart();
    final product = {'id': 'bag-1', 'price': 25000};

    cart.add(product);
    cart.add(product);

    expect(cart.count, 2);
    expect(cart.total, 50000);
  });
}
