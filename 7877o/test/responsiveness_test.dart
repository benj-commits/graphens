import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphen_bags/screens/chat_view.dart';
import 'package:graphen_bags/screens/wishlist_screen.dart';

void main() {
  testWidgets('wishlist does not refetch on rebuild and refreshes on return', (tester) async {
    var productCalls = 0;
    var ids = <String>{'one'};
    Future<Set<String>> loadIds() async => {...ids};
    Future<void> saveIds(Set<String> value) async { ids = {...value}; }
    Future<List<Map<String, dynamic>>> loadProducts() async {
      productCalls++;
      return [
        {'id': 'one', 'name': 'First bag', 'price': 100},
        {'id': 'two', 'name': 'Second bag', 'price': 200},
      ];
    }
    Widget app(bool active) => MaterialApp(home: Scaffold(body: WishlistScreen(
      active: active, loadIds: loadIds, saveIds: saveIds, loadProducts: loadProducts,
    )));

    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.text('First bag'), findsOneWidget);
    expect(productCalls, 1);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(productCalls, 1);
    ids = {'two'};
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(productCalls, 2);
    expect(find.text('First bag'), findsNothing);
    expect(find.text('Second bag'), findsOneWidget);
  });

  testWidgets('wishlist shows loading and allows retry after a failure', (tester) async {
    final pending = Completer<Set<String>>();
    var calls = 0;
    Future<Set<String>> loadIds() {
      calls++;
      return calls == 1 ? pending.future : Future.value(<String>{});
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WishlistScreen(loadIds: loadIds))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('failed'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load wishlist. Please try again.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your wishlist is empty'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('chat prevents duplicate sends and preserves draft on failure', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    Future<void> sendMessage(String text) { calls++; return pending.future; }
    Stream<List<Map<String, dynamic>>> messages(String id) => Stream.value([]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatView(
      customerId: 'customer', asAdmin: false, streamFactory: messages, sendMessage: sendMessage,
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    pending.completeError(StateError('connection failed'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Hello');
    expect(find.textContaining('Check the chat before retrying'), findsOneWidget);
  });

  testWidgets('chat clears the draft only after a confirmed send', (tester) async {
    final pending = Completer<void>();
    Stream<List<Map<String, dynamic>>> messages(String id) => Stream.value([]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatView(
      customerId: 'customer', asAdmin: false, streamFactory: messages, sendMessage: (_) => pending.future,
    ))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Hello');
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });
}
