import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphen_bags/screens/checkout_sheet.dart';
import 'package:graphen_bags/screens/delivery_pin_picker.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const first = LatLng(0.32, 32.58);
  const second = LatLng(0.34, 32.60);

  test('checkout sends both nullable or numeric coordinates', () {
    expect(checkoutPinParams(null), {'p_latitude': null, 'p_longitude': null});
    expect(checkoutPinParams(first), {'p_latitude': 0.32, 'p_longitude': 32.58});
  });

  testWidgets('select, change, clear and save a pin without asking for location', (tester) async {
    var locationCalls = 0;
    LatLng? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => DeliveryPinPicker(
          locate: () async { locationCalls++; return first; },
          mapBuilder: (select, pin) => Column(children: [
            TextButton(onPressed: () => select(first), child: const Text('Map first')),
            TextButton(onPressed: () => select(second), child: const Text('Map second')),
          ]),
        )));
      }, child: const Text('Open picker')),
    ))));
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('No pin selected'), findsOneWidget);
    expect(locationCalls, 0);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save pin')).onPressed, isNull);
    await tester.tap(find.text('Map first'));
    await tester.pump();
    expect(find.text('Selected: 0.32000000, 32.58000000'), findsOneWidget);
    await tester.tap(find.text('Map second'));
    await tester.pump();
    expect(find.text('Selected: 0.34000000, 32.60000000'), findsOneWidget);
    await tester.tap(find.text('Clear pin'));
    await tester.pump();
    expect(find.text('No pin selected'), findsOneWidget);
    await tester.tap(find.text('Map first'));
    await tester.pump();
    await tester.tap(find.text('Save pin'));
    await tester.pumpAndSettle();
    expect(result, first);
    expect(locationCalls, 0);
  });

  for (final message in [
    'Location is off. Turn it on or choose a pin on the map.',
    'Location permission was not granted. Choose a pin on the map instead.',
    'Location permission is blocked. Change it in settings or choose a pin on the map.',
  ]) {
    testWidgets('location failure permits manual selection: $message', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: DeliveryPinPicker(
        locate: () async { calls++; throw LocationUnavailable(message); },
        mapBuilder: (select, pin) => TextButton(onPressed: () => select(first), child: const Text('Manual map pin')),
      )));
      expect(calls, 0);
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('Manual map pin'));
      await tester.pump();
      expect(find.text('Selected: 0.32000000, 32.58000000'), findsOneWidget);
    });
  }

  test('map positions are normalized to the RPC precision and longitude range', () {
    final pin = normalizeDeliveryPin(const LatLng(0.123456789, 32.123456789));
    expect(pin.latitude, 0.12345679);
    expect(pin.longitude, 32.12345679);
  });

  testWidgets('current location is requested only when tapped', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: DeliveryPinPicker(
      locate: () async { calls++; return first; },
      mapBuilder: (select, pin) => const SizedBox.expand(),
    )));
    expect(calls, 0);
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Selected: 0.32000000, 32.58000000'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save pin')).onPressed, isNotNull);
  });

  testWidgets('unknown location error does not block checkout', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DeliveryPinPicker(
      locate: () async => throw Exception('unavailable'),
      mapBuilder: (select, pin) => const SizedBox.expand(),
    )));
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();
    expect(find.text('Could not get your location. Choose a pin on the map or continue without one.'), findsOneWidget);
    expect(find.text('No pin selected'), findsOneWidget);
  });
}
