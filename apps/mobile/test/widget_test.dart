import 'package:fan_os/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launch page exposes both entry paths', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FanOsApp()));
    await tester.pump();

    expect(find.text('Fan OS'), findsOneWidget);
    expect(find.text('开启旅程'), findsOneWidget);
    expect(find.text('游客体验'), findsOneWidget);
  });
}
