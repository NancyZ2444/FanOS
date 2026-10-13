import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_feedback_models.dart';
import 'package:fan_os/core/data/user_data_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/onboarding/presentation/favorite_setup_page.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:fan_os/features/profile/presentation/edit_profile_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(ProviderContainer container, Widget home) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: FanOsTheme.light, home: home),
      );

  test('catalog models retain every published default image', () {
    final idol = IdolProfile.fromJson({
      'id': 'idol',
      'name': 'Idol',
      'image_url': 'https://assets.test/idol.jpg',
      'group_ids': ['group'],
    });
    final group = FanGroup.fromJson({
      'id': 'group',
      'name': 'Group',
      'image_url': 'https://assets.test/group.jpg',
    });
    final album = CatalogAlbum.fromJson({
      'id': 'album',
      'name': 'Album',
      'image_url': 'https://assets.test/album.jpg',
    });
    final event = CatalogEvent.fromJson({
      'id': 'event',
      'name': 'Event',
      'image_url': 'https://assets.test/event.jpg',
    });
    final merch = CatalogOther.fromJson({
      'id': 'merch',
      'name': 'Merch',
      'image_url': 'https://assets.test/merch.jpg',
    });
    expect(idol.imageUrl, endsWith('idol.jpg'));
    expect(idol.groupIds, ['group']);
    expect(group.imageUrl, endsWith('group.jpg'));
    expect(album.frontImageUrl, endsWith('album.jpg'));
    expect(event.imageUrl, endsWith('event.jpg'));
    expect(merch.imageUrl, endsWith('merch.jpg'));
  });

  testWidgets(
    'choose two favorites saves exactly two, without hidden defaults',
    (tester) async {
      phone(tester);
      final repository = _UserRepository();
      final container = ProviderContainer(
        overrides: [userDataRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      // Old unpublished IDs must not inflate the selected counter or the saved list.
      container.read(favoritesProvider.notifier).hydrate({
        'archived-1',
        'archived-2',
      }, 'archived-1');
      final router = GoRouter(
        initialLocation: '/favorites',
        routes: [
          GoRoute(
            path: '/favorites',
            builder: (_, _) => const FavoriteSetupPage(),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('saved-home')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: FanOsTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('完成（已选 0）'), findsOneWidget);
      await tester.tap(find.text('Aria'));
      await tester.pump();
      await tester.tap(find.text('Lin'));
      await tester.pump();
      expect(find.text('完成（已选 2）'), findsOneWidget);
      expect(container.read(favoritesProvider).selectedIds, {
        'archived-1',
        'archived-2',
      });
      await tester.tap(find.text('完成（已选 2）'));
      await tester.pumpAndSettle();
      expect(repository.savedIds, {'idol-aria', 'idol-lin'});
      expect(container.read(favoritesProvider).selectedIds, {
        'idol-aria',
        'idol-lin',
      });
      expect(find.text('saved-home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('public and unavailable profiles can return to previous page', (
    tester,
  ) async {
    phone(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      app(
        container,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfilePage(userId: 'user-mint'),
                    ),
                  ),
                  child: const Text('open-profile'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfilePage(userId: 'missing'),
                    ),
                  ),
                  child: const Text('open-missing'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final label in ['open-profile', 'open-missing']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open-profile'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('group member cards use compact fixed height', (tester) async {
    phone(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      app(container, const GroupDetailPage(groupId: 'group-lumina')),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .mainAxisExtent,
      82,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile renders persisted cover and editor supports removal', (
    tester,
  ) async {
    phone(tester);
    final repository = _UserRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        userDataRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier);
    await controller.login(LoginMethod.phone);
    await controller.saveProfileImage('background', '/cover.jpg');
    await tester.pumpWidget(app(container, const ProfilePage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-background')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FanImage && widget.imageUrl == '/cover.jpg',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(app(container, const EditProfilePage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choose-profile-background')), findsOneWidget);
    await tester.tap(find.text('移除背景'));
    await tester.pump();
    await controller.saveProfileImage('background', null);
    expect(repository.savedImageKind, 'background');
    expect(container.read(sessionProvider).backgroundPath, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'feedback selection filters members and clears previous idol on group change',
    (tester) async {
      phone(tester);
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).login(LoginMethod.phone);
      await tester.pumpWidget(
        app(
          container,
          ScanFeedbackPage(
            args: ScanFeedbackRouteArgs(
              session: const ScanSession(id: 'session', detectedCards: []),
              detectedCard: const DetectedScanCard(
                id: 'detected',
                cropRegion: ScanCropRegion(x: 0, y: 0, width: 1, height: 1),
                candidates: [],
                status: ScanRecognitionStatus.unrecognized,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final group = find.widgetWithText(TextField, '所属组合');
      await tester.ensureVisible(group);
      await tester.enterText(group, 'LUMINA');
      await tester.pumpAndSettle();
      await tester.tap(find.text('LUMINA').last);
      await tester.pumpAndSettle();
      final idol = find.widgetWithText(TextField, 'Idol');
      await tester.ensureVisible(idol);
      await tester.tap(idol);
      await tester.pumpAndSettle();
      expect(find.text('Aria · LUMINA'), findsOneWidget);
      expect(find.text('Yuna · ASTER'), findsNothing);
      await tester.tap(find.text('Aria · LUMINA'));
      await tester.pumpAndSettle();
      await tester.enterText(group, 'ASTER');
      await tester.pumpAndSettle();
      await tester.tap(find.text('ASTER').last);
      await tester.pumpAndSettle();
      final nextIdol = find.widgetWithText(TextField, 'Idol');
      expect(tester.widget<TextField>(nextIdol).controller!.text, isEmpty);
      await tester.tap(nextIdol);
      await tester.pumpAndSettle();
      expect(find.text('Yuna · ASTER'), findsOneWidget);
      expect(find.text('Aria · LUMINA'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('feedback history exposes status and review outcome', (
    tester,
  ) async {
    phone(tester);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        scanRepositoryProvider.overrideWithValue(_ScanRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login(LoginMethod.phone);
    await tester.pumpWidget(app(container, const ScanFeedbackHistoryPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('待处理'), findsWidgets);
    expect(find.textContaining('已完成'), findsWidgets);
    await tester.tap(find.text('Lin'));
    await tester.pumpAndSettle();
    expect(find.text('处理说明：已补充对应版本'), findsOneWidget);
    expect(find.textContaining('已收录：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _UserRepository extends MockUserDataRepository {
  Set<String>? savedIds;
  String? savedImageKind;
  @override
  Future<void> updateFavorites(Set<String> idolIds, String? primaryId) async =>
      savedIds = {...idolIds};
  @override
  Future<String?> saveProfileImage(String kind, String? path) async {
    savedImageKind = kind;
    return path;
  }
}

class _ScanRepository extends MockScanRepository {
  @override
  Future<ScanFeedbackPageData> fetchFeedbackHistory({int offset = 0}) async =>
      ScanFeedbackPageData(
        items: [
          ScanFeedbackRecord(
            id: 'pending',
            status: 'pending',
            createdAt: DateTime(2026, 10, 10),
            updatedAt: DateTime(2026, 10, 10),
            idolName: 'Aria',
          ),
          ScanFeedbackRecord(
            id: 'resolved',
            status: 'resolved',
            createdAt: DateTime(2026, 10, 9),
            updatedAt: DateTime(2026, 10, 10),
            idolName: 'Lin',
            reviewReason: '已补充对应版本',
            matchedCard: DemoCatalog.cards.first,
          ),
        ],
      );
}
