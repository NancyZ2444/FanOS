import 'package:fan_os/app/theme.dart';
import 'package:fan_os/features/catalog/presentation/catalog_profile_tab.dart';
import 'package:fan_os/features/feedback/correction_page.dart';
import 'package:fan_os/features/feedback/feedback_data.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _fields = <FeedbackJson>[
  {
    'key': 'description',
    'label': '简介',
    'type': 'long_text',
    'section': 'intro',
    'current': '第一段简介\n\n第二段简介',
    'current_display': '第一段简介\n\n第二段简介',
    'max_length': 2000,
  },
  {
    'key': 'name',
    'label': '官方名称',
    'type': 'text',
    'section': 'basic',
    'current': 'Official Name',
    'current_display': 'Official Name',
    'max_length': 180,
  },
  {
    'key': 'name_ko',
    'label': '韩文名称',
    'type': 'text',
    'section': 'basic',
    'current': '',
    'current_display': '',
    'max_length': 180,
  },
  {
    'key': 'birth_date',
    'label': '生日',
    'type': 'date',
    'section': 'basic',
    'current': '2000-01-02',
    'current_display': '2000-01-02',
    'max_length': 180,
  },
  {
    'key': 'debut_date',
    'label': '出道日期',
    'type': 'date',
    'section': 'basic',
    'current': '2020-03-04',
    'current_display': '2020-03-04',
    'max_length': 180,
  },
  {
    'key': 'career_text',
    'label': '从艺历程',
    'type': 'long_text',
    'section': 'career',
    'current': '2020年\n正式出道\n\n2025年\n完整经历正文',
    'current_display': '2020年\n正式出道\n\n2025年\n完整经历正文',
    'max_length': 20000,
  },
  {
    'key': 'honors_text',
    'label': '荣誉记录',
    'type': 'long_text',
    'section': 'honors',
    'current': '',
    'current_display': '',
    'max_length': 20000,
  },
];

class _Feedback extends FeedbackRepository {
  _Feedback() : super(ApiClient());
  @override
  Future<FeedbackJson> get(String path, {FeedbackJson? query}) async => {
    'entity_type': 'idols',
    'entity_id': 'test',
    'name': 'Official Name',
    'version': 'v1',
    'profile': true,
    'fields': _fields,
  };
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'dossier four sections, independent dates and empty content fit $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogProfileProvider(
                'idols/test',
              ).overrideWith((ref) async => {'fields': _fields, 'revision': 1}),
            ],
            child: MaterialApp(
              theme: FanOsTheme.light,
              home: const Scaffold(
                body: CatalogProfileTab(kind: 'idols', entityId: 'test'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('编辑资料'), findsNothing);
        expect(find.text('修订历史'), findsNothing);
        expect(find.text('资料反馈'), findsOneWidget);
        expect(find.byTooltip('修订历史'), findsOneWidget);
        expect(find.text('第一段简介\n\n第二段简介'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('生日'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('2000-01-02'), findsOneWidget);
        expect(find.text('2020-03-04'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('暂无荣誉记录'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('暂无荣誉记录'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'profile editor includes empty names and prefills complete long text',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedbackRepositoryProvider.overrideWithValue(_Feedback()),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: const CorrectionPage(
              entityType: 'idols',
              entityId: 'test',
              section: 'career',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, '从艺历程'));
      await tester.pumpAndSettle();
      final editor = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((w) => w.maxLength == 20000);
      expect(editor.controller!.text, _fields[5]['current']);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('基本资料').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, '韩文名称'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, '生日'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(CheckboxListTile, '出道日期'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.widgetWithText(CheckboxListTile, '出道日期'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('profile load failure exposes retry', (tester) async {
    var tries = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          catalogProfileProvider('groups/test').overrideWith((ref) async {
            if (tries++ == 0) throw Exception('temporary error');
            return {'fields': _fields};
          }),
        ],
        child: MaterialApp(
          theme: FanOsTheme.light,
          home: const Scaffold(
            body: CatalogProfileTab(kind: 'groups', entityId: 'test'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('资料暂时无法加载'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('编辑资料'), findsNothing);
  });
}
