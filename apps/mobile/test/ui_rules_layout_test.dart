import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/search_page.dart';
import 'package:fan_os/features/collection/presentation/collection_page.dart';
import 'package:fan_os/features/feed/presentation/feed_page.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:fan_os/features/onboarding/presentation/favorite_setup_page.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:fan_os/features/onboarding/presentation/privacy_page.dart';
import 'package:fan_os/features/profile/presentation/edit_profile_page.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:fan_os/features/scan/presentation/scan_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

void main() {
  final session = ScanSession(
    id: 'layout-scan',
    detectedCards: [
      DetectedScanCard(
        id: 'one',
        cropRegion: const ScanCropRegion(x: 0, y: 0, width: 1, height: 1),
        status: ScanRecognitionStatus.recommended,
        candidates: [
          ScanCandidate(card: DemoCatalog.cards.first, similarity: .96),
        ],
      ),
    ],
  );
  final pages = <String, Widget>{
    'home': const HomePage(),
    'catalog': const CatalogPage(),
    'group': const GroupDetailPage(groupId: 'group-lumina'),
    'idol': const IdolDetailPage(idolId: 'idol-aria'),
    'card': const CardDetailPage(cardId: 'card-aria-01'),
    'search': const SearchPage(),
    'collection': const CollectionPage(),
    'profile': const ProfilePage(),
    'edit-profile': const EditProfilePage(),
    'favorites': const FavoriteSetupPage(),
    'login': const LoginPage(),
    'privacy': const PrivacyPage(),
    'feed': const FeedPage(),
    'scan-result': ScanResultPage(session: session),
  };
  for (final size in [(320.0, 1.4), (430.0, 1.0)]) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} fits width ${size.$1} text scale ${size.$2}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(size.$1, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
        );
        addTearDown(container.dispose);
        await container.read(sessionProvider.notifier).login(LoginMethod.phone);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: FanOsTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(size.$2)),
                child: child!,
              ),
              home: entry.value,
            ),
          ),
        );
        // Static skeletons do not schedule frames during the mock network delay.
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'no historical members and empty group/idol cards have accurate states',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = CatalogBundle(
        groups: [
          FanGroup.fromJson({
            'id': 'g',
            'name': 'ATEEZ',
            'member_ids': ['i'],
            'former_member_ids': [],
          }),
        ],
        idols: [
          IdolProfile.fromJson({
            'id': 'i',
            'name': 'SEONGHWA',
            'group_name': 'ATEEZ',
          }),
        ],
        cards: [],
      );
      Future<void> mount(Widget page) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [catalogProvider.overrideWith((ref) async => catalog)],
            child: MaterialApp(theme: FanOsTheme.light, home: page),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(const GroupDetailPage(groupId: 'g'));
      expect(find.textContaining('过往成员'), findsNothing);
      expect(find.textContaining('历史成员'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, '小卡'));
      await tester.pumpAndSettle();
      expect(find.text('暂未收录小卡'), findsOneWidget);
      await mount(const IdolDetailPage(idolId: 'i'));
      expect(find.text('暂未收录小卡'), findsOneWidget);
      expect(find.text('SEONGHWA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
