import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/catalog_tags.dart';
import 'package:fan_os/features/catalog/presentation/card_gallery_page.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const cardTag = CatalogTag(id: 'card-tag', name: 'POB', entityType: 'CARD');
const unrelatedTag = CatalogTag(
  id: 'other-card-tag',
  name: 'Concert',
  entityType: 'CARD',
);
CollectibleCard card(String id, String group, CatalogTag tag) =>
    CollectibleCard(
      id: id,
      title: id,
      idolId: 'idol-aria',
      idolName: 'Aria',
      groupId: group,
      groupName: group,
      source: 'Brand',
      sourceEntityType: 'OTHER',
      sourceEntityId: 'brand',
      cardType: 'Regular',
      version: 'V1',
      releaseDate: '2026-10-11',
      region: 'Korea',
      colorStart: 0xFF8B7CFF,
      colorEnd: 0xFF3843A8,
      tags: [tag],
    );
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'Other reads six fields and preserves disabled historical tags by identity',
    () {
      final other = CatalogOther.fromJson({
        'id': 'other-1',
        'name': '展示名称',
        'original_name': 'Original',
        'start_date': '2026-01-01',
        'end_date': '2026-02-01',
        'description': '说明',
        'tag_details': [
          {
            'id': 'other-pob',
            'name': 'POB',
            'entity_type': 'OTHER',
            'status': 'DISABLED',
            'source': 'USER_SUBMITTED',
          },
        ],
      });
      expect(other.displayName, '展示名称');
      expect(other.originalName, 'Original');
      expect(other.tags.single.id, isNot(cardTag.id));
      expect(other.tags.single.status, 'DISABLED');
    },
  );
  testWidgets(
    'Card tag filters contain only tags from current group and source results',
    (tester) async {
      phone(tester);
      final bundle = CatalogBundle(
        groups: DemoCatalog.groups,
        idols: DemoCatalog.idols,
        albums: const [],
        events: const [],
        others: const [CatalogOther(id: 'brand', name: 'Brand')],
        cards: [
          card('one', 'group-lumina', cardTag),
          card('two', 'group-nova', unrelatedTag),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [catalogProvider.overrideWith((_) async => bundle)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const CardGalleryPage(groupId: 'group-lumina'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-card-filters')));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      final scroll = find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.text('Card Tags'),
        250,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'POB'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Concert'), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'POB'));
      await tester.tap(find.byKey(const Key('apply-card-filters')));
      await tester.pumpAndSettle();
      expect(find.text('1 张小卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('new user tag is added only to this form and deduplicated', (
    tester,
  ) async {
    phone(tester);
    var values = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogTagOptionsProvider('OTHER')
              .overrideWith((_) async => const []),
        ],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => UserTagPicker(
                entityType: 'OTHER',
                values: values,
                onChanged: (v) => set(() => values = v),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('catalog-tag-search')),
      'Lucky  Draw',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('catalog-tag-search')),
      'lucky draw',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-add-tag')));
    await tester.pumpAndSettle();
    expect(values, ['Lucky Draw']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Other supplement includes its selected group association', (
    tester,
  ) async {
    phone(tester);
    final repository = _MissingRepository();
    final container = ProviderContainer(
      overrides: [
        catalogProvider.overrideWith((_) async => DemoCatalog.bundle),
        feedbackRepositoryProvider.overrideWithValue(repository),
        catalogTagOptionsProvider('OTHER').overrideWith((_) async => const []),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(sessionProvider.notifier).login(LoginMethod.phone),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => const CatalogMissingFeedbackPage(
                      args: CatalogMissingFeedbackRouteArgs(
                        source: '其他',
                        groupId: 'group-lumina',
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('组合/艺人'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('catalog-missing-name')),
      'Brand Collaboration',
    );
    await tester.enterText(
      find.byKey(const Key('catalog-missing-notes')),
      '活动说明',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('others:tags')));
    await tester.enterText(
      find.byKey(const ValueKey('others:tags')),
      'Japan Exclusive',
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('submit-catalog-missing-feedback')),
    );
    await tester.tap(find.byKey(const Key('submit-catalog-missing-feedback')));
    await tester.pumpAndSettle();
    final request = repository.submissions.single;
    expect(request['kind'], 'MISSING_CATALOG');
    expect(request['entity_type'], 'others');
    final values = {
      for (final field in feedbackItems(request['fields']))
        field['key']: field['value'],
    };
    expect(values['artists'], [
      {'type': 'groups', 'id': 'group-lumina'},
    ]);
    expect(values['tags'], ['Japan Exclusive']);
    expect(tester.takeException(), isNull);
  });
}

class _MissingRepository extends FeedbackRepository {
  _MissingRepository() : super(ApiClient());
  final submissions = <FeedbackJson>[];
  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async => {
    'fields': [
      {'key': 'name', 'label': '名称', 'type': 'text', 'required': true},
      {
        'key': 'artists',
        'label': '组合/艺人',
        'type': 'multi_reference',
        'reference': 'actors',
      },
      {'key': 'tags', 'label': '标签', 'type': 'list'},
    ],
  };
  @override
  Future<FeedbackJson> post(String path, FeedbackJson body) async {
    submissions.add(body);
    return {'id': 'missing-other'};
  }
}
