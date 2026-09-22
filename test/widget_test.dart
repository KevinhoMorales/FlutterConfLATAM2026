import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_demo/main.dart';
import 'package:flutter_watch_demo/services/watch_service.dart';

void main() {
  testWidgets('shows the Watch demo screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FlutterWatchApp());
    await tester.pump();

    expect(find.text('Flutter ↔ Apple Watch'), findsOneWidget);
    expect(find.text('Send Message to Watch'), findsOneWidget);
    expect(find.text('Last message from Apple Watch'), findsOneWidget);
  });

  test('WatchService reports unsupported off iOS', () async {
    final service = WatchService();
    final status = await service.getStatus();
    expect(status.supported, isFalse);
    expect(status.label, 'Watch not available');
  });
}
