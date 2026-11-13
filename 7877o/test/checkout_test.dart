import 'package:flutter_test/flutter_test.dart';
import 'package:graphen_bags/screens/checkout_sheet.dart';

void main() {
  test('checkout request IDs are UUID v4 and distinct', () {
    final format = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final ids = List.generate(100, (_) => newCheckoutRequestId());
    expect(ids.toSet().length, ids.length);
    expect(ids.every(format.hasMatch), isTrue);
  });

  test('delivery date uses a local calendar date', () {
    expect(checkoutDate(DateTime(2026, 1, 2, 23, 59)), '2026-01-02');
  });
}
