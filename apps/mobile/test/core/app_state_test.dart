import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily draw is capped at three unique cards', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(favoritesProvider.notifier).hydrate({
      'idol-aria',
      'idol-lin',
      'idol-mina',
      'idol-yuna',
    }, 'idol-aria');

    final controller = container.read(dailyCardProvider.notifier);
    await controller.draw();
    await controller.draw();
    await controller.draw();
    await controller.draw();

    final state = container.read(dailyCardProvider);
    expect(state.drawnCards, hasLength(3));
    expect(state.drawnCards.map((card) => card.id).toSet(), hasLength(3));
    expect(state.remaining, 0);
    expect(
      state.drawnCards.every(
        (card) =>
            container.read(favoritesProvider).selectedIds.contains(card.idolId),
      ),
      isTrue,
    );
  });

  test('owned and wishlist may coexist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(collectionProvider.notifier);
    controller.toggleWishlist('card-aria-01');

    final state = container.read(collectionProvider);
    expect(state.isOwned('card-aria-01'), isTrue);
    expect(state.isWished('card-aria-01'), isTrue);
  });
}
