import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphen_bags/screens/customer_shell.dart';
import 'package:graphen_bags/theme.dart';

void main() {
  test('brand text colors have accessible contrast on cream and white', () {
    double contrast(Color a, Color b) {
      final values = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (values.last + .05) / (values.first + .05);
    }
    expect(contrast(ink, cream), greaterThanOrEqualTo(4.5));
    expect(contrast(gold, cream), greaterThanOrEqualTo(4.5));
    expect(contrast(gold, Colors.white), greaterThanOrEqualTo(4.5));
    expect(contrast(ink, Colors.white), greaterThanOrEqualTo(4.5));
  });

  test('WhatsApp draft uses existing support number and only selected topic', () {
    final uri = supportWhatsAppUri('Order question');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/256779572987');
    expect(uri.queryParameters, {'text': 'Hello Graphen Bags, I need help with: Order question.'});
  });

  testWidgets('support suggests current section and offers chat', (tester) async {
    var chatOpened = false;
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: SupportSheet(
        initialTopic: 3,
        onChat: () => chatOpened = true,
        onWhatsApp: (uri) async { opened = uri; },
      )),
    ));
    expect(find.textContaining('WhatsApp draft: Hello Graphen Bags, I need help with: Order question.'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue to WhatsApp'));
    await tester.tap(find.text('Continue to WhatsApp'));
    await tester.pump();
    expect(opened?.queryParameters['text'], contains('Order question'));
    await tester.ensureVisible(find.text('Use in-app chat instead'));
    await tester.tap(find.text('Use in-app chat instead'));
    expect(chatOpened, isTrue);
  });
}
