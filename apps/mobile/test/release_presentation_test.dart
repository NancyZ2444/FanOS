import 'package:fan_os/app/router.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/config/feature_flags.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/name_sort.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_list_page.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:fan_os/features/notification/presentation/notifications_page.dart';
import 'package:fan_os/features/profile/presentation/profile_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'artist names follow the complete hierarchy, trimming and deduplicating',
    () {
      final fields = [
        'name_translated',
        'name',
        'name_ko',
        'name_en',
        'real_name',
      ];
      final values = ['宋雨琦', 'Yuqi', '우기', 'YUQI English', '宋雨琦本名'];
      for (var first = 0; first < fields.length; first++) {
        final idol = IdolProfile.fromJson({
          'id': 'yuqi',
          for (var i = first; i < fields.length; i++)
            fields[i]: ' ${values[i]} ',
        });
        expect(idol.displayName, values[first]);
        expect(
          idol.secondaryName,
          first + 1 < values.length ? values[first + 1] : '',
        );
      }
      final duplicate = IdolProfile.fromJson({
        'id': 'y',
        'name_translated': 'Yuqi',
        'name': ' YUQI ',
        'name_ko': '우기',
      });
      expect(duplicate.secondaryName, '우기');
      expect(IdolProfile.fromJson({'id': 'empty'}).displayName, '未命名艺人');
    },
  );

  test('A-Z uses the visible Chinese title in pinyin, not the original English name', () {
    final names = ['张三', 'Alice', '宋雨琦', '方灿'];
    names.sort(compareDisplayNames);
    expect(names, ['Alice', '方灿', '宋雨琦', '张三']);
    expect(compareDisplayNames('Yuqi', 'yuqi'), isNotNull);
  });

  test('card display titles never fall back to any legacy name', () {
    const requiredFields = <String, dynamic>{
      'idol_name': '',
      'group_name': '',
      'source': '',
      'version': '',
      'card_type': '',
      'release_date': '',
      'region': '',
    };
    final card = CollectibleCard.fromJson({
      ...requiredFields,
      'id': 'c',
      'title': 'Gaeul20260501001',
      'title_en': 'Legacy English',
      'title_translated': '旧名字',
      'source': 'IVE SWITCH',
      'version': 'Digital (Spotify)',
      'card_type': 'Regular',
    });
    expect(card.displayTitle, 'IVE SWITCH · Digital (Spotify) · Regular');
    expect(card.secondaryTitle, isEmpty);
    expect(card.title, 'Gaeul20260501001');
    final blank = CollectibleCard.fromJson({
      ...requiredFields,
      'id': 'empty',
      'title': 'NEVER SHOW',
      'card_type': '',
    });
    expect(blank.displayTitle, '小卡资料待补充');
  });

  testWidgets(
    'release UI hides all feed surfaces without requesting the feed',
    (tester) async {
      expect(idolFeedEnabled, isFalse);
      var feedAccess = 0;
      final container = ProviderContainer(
        overrides: [
          socialFeedRepositoryProvider.overrideWith((ref) {
            feedAccess++;
            throw StateError('Hidden feed must not load');
          }),
        ],
      );
      addTearDown(container.dispose);
      for (final page in const <Widget>[
        HomePage(),
        GroupDetailPage(groupId: 'group-lumina'),
        IdolDetailPage(idolId: 'idol-aria'),
        NotificationsPage(),
      ]) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(theme: FanOsTheme.light, home: page),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(Tab, '动态'), findsNothing);
        expect(find.textContaining('本命动态'), findsNothing);
        expect(find.text('接收 Push'), findsNothing);
        expect(find.byKey(const Key('home-feed-favorite-hint')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(feedAccess, 0);
    },
  );

  testWidgets('old feed routes redirect to home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: FanOsTheme.light,
          routerConfig: fanOsRouter,
        ),
      ),
    );
    for (final path in ['/feed', '/feed/post/old-post']) {
      fanOsRouter.go(path);
      await tester.pumpAndSettle();
      expect(fanOsRouter.routeInformationProvider.value.uri.path, '/home');
      expect(find.textContaining('本命动态'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('artist list titles and subtitles use new hierarchy', (
    tester,
  ) async {
    final idols = [
      IdolProfile.fromJson({
        'id': 'z',
        'name': 'Aaron',
        'name_translated': '张三',
        'name_ko': '장',
      }),
      IdolProfile.fromJson({
        'id': 's',
        'name': 'Yuqi',
        'name_translated': '宋雨琦',
        'name_ko': '우기',
      }),
      IdolProfile.fromJson({
        'id': 'f',
        'name': 'Bang Chan',
        'name_translated': '方灿',
        'name_ko': '방찬',
      }),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith(
            (ref) async => CatalogBundle(idols: idols, groups: [], cards: []),
          ),
        ],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const CatalogListPage(type: CatalogListType.idols),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('方灿')).dy,
      lessThan(tester.getTopLeft(find.text('宋雨琦')).dy),
    );
    expect(
      tester.getTopLeft(find.text('宋雨琦')).dy,
      lessThan(tester.getTopLeft(find.text('张三')).dy),
    );
    expect(find.textContaining('Yuqi'), findsOneWidget);
    expect(find.textContaining('우기'), findsNothing);
  });

  testWidgets(
    'profile backdrop preserves a clear top and progressively masked blur',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 390,
            height: 350,
            child: ProfileBackdrop(imageUrl: '/tmp/no-profile-test-image.jpg'),
          ),
        ),
      );
      final masks = tester
          .widgetList<ShaderMask>(find.byType(ShaderMask))
          .toList();
      expect(masks, hasLength(2));
      expect(masks.every((mask) => mask.blendMode == BlendMode.dstIn), isTrue);
      expect(find.byType(ImageFiltered), findsNWidgets(2));
      expect(find.byType(IgnorePointer), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
