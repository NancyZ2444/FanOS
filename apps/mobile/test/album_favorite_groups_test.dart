import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/features/albums/data/album_favorites_repository.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/presentation/album_favorite_sheet.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth implements AuthRepository {
  @override
  Future<void> login(LoginMethod method, {String? phone, String? code}) async {}
}

class _Favorites implements AlbumFavoritesRepository {
  final groups = <AlbumFavoriteFolder>[];
  final saves = <(String, String?, bool)>[];
  final lists = <(String?, String?, int)>[];
  bool failSave = false;
  @override
  Future<List<AlbumFavoriteFolder>> folders({String? userId}) async => groups;
  @override
  Future<AlbumFavoriteFolder> saveFolder(
    String name,
    bool isPublic, {
    String? id,
  }) async {
    final folder = AlbumFavoriteFolder(
      id: id ?? 'g${groups.length}',
      name: name,
      isPublic: isPublic,
    );
    groups.removeWhere((f) => f.id == id);
    groups.add(folder);
    return folder;
  }

  @override
  Future<AlbumShelfData> list({
    String? userId,
    String? groupId,
    int offset = 0,
  }) async {
    lists.add((userId, groupId, offset));
    return AlbumShelfData([]);
  }

  @override
  Future<void> save(
    String albumId,
    String? groupId, {
    bool move = false,
  }) async {
    if (failSave) throw Exception('网络暂时不可用');
    saves.add((albumId, groupId, move));
  }

  @override
  Future<void> remove(String albumId) async {}
}

Future<void> _mount(WidgetTester tester, _Favorites repo, {Widget? page}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      albumFavoritesRepositoryProvider.overrideWithValue(repo),
      albumRepositoryProvider.overrideWithValue(MockAlbumRepository()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sessionProvider.notifier).login(LoginMethod.phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FanOsTheme.light,
        home: Scaffold(
          body:
              page ??
              Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () =>
                          showAlbumFavoriteSheet(context, 'album-1'),
                      child: const Text('收藏'),
                    ),
                    TextButton(
                      onPressed: () => showAlbumFavoriteSheet(
                        context,
                        'album-1',
                        move: true,
                        initialGroupId: 'g0',
                      ),
                      child: const Text('移动'),
                    ),
                  ],
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create private folder during favorite, select it and save', (
    tester,
  ) async {
    final repo = _Favorites();
    await _mount(tester, repo);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('未分组'), findsOneWidget);
    await tester.tap(find.text('新建分组'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.enterText(find.byType(TextField), '舞台收藏');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();
    expect(repo.groups.single.isPublic, isFalse);
    expect(repo.saves, isEmpty);
    expect(find.text('舞台收藏'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saves.single, ('album-1', 'g0', false));
    expect(find.text('收藏到分组'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'move keeps selection on network failure, can retry or cancel without saving',
    (tester) async {
      final repo = _Favorites()
        ..groups.add(const AlbumFavoriteFolder(id: 'g0', name: '私密收藏'));
      await _mount(tester, repo);
      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, '私密收藏'),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('未分组'));
      repo.failSave = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('网络暂时不可用'), findsOneWidget);
      expect(repo.saves, isEmpty);
      repo.failSave = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.saves.single, ('album-1', null, true));
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(repo.saves.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile shelf has two categories, no search or drafts, favorite-time sort and editable privacy',
    (tester) async {
      final repo = _Favorites()
        ..groups.add(const AlbumFavoriteFolder(id: 'g0', name: '我的收藏'));
      await _mount(
        tester,
        repo,
        page: const AlbumShelfBody(profileMode: true, showTitle: false),
      );
      expect(find.text('我的相册'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('草稿'), findsNothing);
      expect(find.text('最近更新'), findsOneWidget);
      await tester.tap(find.text('最近更新'));
      await tester.pumpAndSettle();
      expect(find.text('最近创建'), findsOneWidget);
      await tester.tap(find.text('名称'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我收藏的'));
      await tester.pumpAndSettle();
      expect(find.text('按收藏时间'), findsOneWidget);
      expect(find.text('名称'), findsNothing);
      await tester.tap(find.text('我的收藏'));
      await tester.pumpAndSettle();
      expect(repo.lists.last, (null, 'g0', 0));
      await tester.tap(find.byTooltip('编辑分组与可见性'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.groups.single.isPublic, isTrue);
      expect(find.byIcon(Icons.public), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'visitor album folders are read only and queried for the profile owner',
    (tester) async {
      final repo = _Favorites()
        ..groups.add(
          const AlbumFavoriteFolder(id: 'g0', name: '公开收藏', isPublic: true),
        );
      await _mount(
        tester,
        repo,
        page: const AlbumShelfBody(profileMode: true, userId: 'other-user'),
      );
      await tester.tap(find.text('TA 收藏的'));
      await tester.pumpAndSettle();
      expect(find.text('未分组'), findsNothing);
      expect(find.byTooltip('新建收藏分组'), findsNothing);
      await tester.tap(find.text('公开收藏'));
      await tester.pumpAndSettle();
      expect(repo.lists.last, ('other-user', 'g0', 0));
      expect(find.byTooltip('编辑分组与可见性'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
