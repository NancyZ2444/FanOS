import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'owned and wishlist states stay independent and quantity can change',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_InstantAuthRepository()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      expect(
        container.read(collectionProvider).isWished('card-lin-01'),
        isTrue,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const CardDetailPage(cardId: 'card-lin-01'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我有这张'));
      await tester.pumpAndSettle();
      var collection = container.read(collectionProvider);
      expect(collection.quantity('card-lin-01'), 1);
      expect(collection.isWished('card-lin-01'), isTrue);

      await tester.tap(find.text('已拥有 1'));
      await tester.pumpAndSettle();
      expect(find.text('管理拥有数量'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quantity-plus')));
      await tester.tap(find.text('保存数量'));
      await tester.pumpAndSettle();

      collection = container.read(collectionProvider);
      expect(collection.quantity('card-lin-01'), 2);
      expect(collection.isWished('card-lin-01'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _InstantAuthRepository implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}
