import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/albums/data/album_draft_store.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/data/album_resources.dart';
import 'package:fan_os/features/albums/presentation/album_color_extraction_sheet.dart';
import 'package:fan_os/features/albums/presentation/album_editor_panels.dart';
import 'package:fan_os/features/albums/presentation/album_editor_page.dart';
import 'package:fan_os/features/albums/presentation/album_moderation_banner.dart';
import 'package:fan_os/features/albums/presentation/album_resource_tile.dart';
import 'package:fan_os/features/albums/presentation/album_widgets.dart';
import 'package:fan_os/features/albums/state/album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AlbumJson _quotaJson() => {
  'album_count': 1,
  'max_album_count': 10,
  'max_page_per_album': 10,
  'max_card_per_page': 9,
  'color_extraction': {
    'daily_limit': 3,
    'monthly_limit': 20,
    'daily_used': 1,
    'monthly_used': 2,
    'timezone': 'Asia/Shanghai',
  },
};
AlbumJson _resource(
  String id, {
  String kind = 'BACKGROUND',
  String scene = 'ALBUM_PAGE',
  String member = 'ALL',
  bool available = true,
  bool preview = true,
}) => {
  'id': id,
  'name': id,
  'kind': kind,
  'scene': scene,
  'membership': member,
  'available': available,
  'locked_preview': preview,
  'status': 'PUBLISHED',
  'config': albumBackground(['#AABBCC']),
};

class _MemoryStore extends AlbumDraftStore {
  _MemoryStore() : super('p0-test');
  final Map<String, AlbumJson> data = {};
  @override
  Future<AlbumJson?> read(String key) async => data[key];
  @override
  Future<void> write(String key, AlbumJson value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

class _ReviewRepo extends MockAlbumRepository {
  String? reviewedName;
  @override
  Future<PhotocardAlbum> requestReview(PhotocardAlbum album) async {
    reviewedName = (await get(album.id)).name;
    return super.requestReview(album);
  }
}

class _ExtractionRepo extends MockAlbumRepository {
  final requestIds = <String>[];
  @override
  Future<AlbumQuota> quota() async => AlbumQuota.fromJson(_quotaJson());
  @override
  Future<AlbumExtractedColors> extractColors({
    required String requestId,
    String? cardId,
    Uint8List? bytes,
    String? fileName,
  }) async {
    requestIds.add(requestId);
    if (requestIds.length == 1) {
      throw const ApiException('NETWORK_ERROR', '网络暂时不可用，请重试');
    }
    return AlbumExtractedColors(['#112233', '#445566'], await quota());
  }
}

void main() {
  test('old quota and moderation payloads remain compatible; new daily/month fields parse', () {
    final legacy = _quotaJson()..remove('color_extraction');
    expect(AlbumQuota.fromJson(legacy).colorExtraction, isNull);
    final q = AlbumQuota.fromJson(_quotaJson()).colorExtraction!;
    expect(q.dailyRemaining, 2);
    expect(q.monthlyRemaining, 18);
    expect(q.timezone, 'Asia/Shanghai');
    expect(
      PhotocardAlbum({'id': 'old', 'is_moderated': true}).moderationStatus,
      'RESTRICTED',
    );
    expect(
      PhotocardAlbum({'id': 'new', 'moderation_status': 'OFFLINE'})
          .moderationLabel,
      '已下架',
    );
  });

  test(
    'resource choices isolate scene, hide offline and hidden member materials',
    () {
      final rows = [
        _resource('cover', scene: 'ALBUM_COVER'),
        _resource('page', scene: 'ALBUM_PAGE'),
        _resource('cards', scene: 'CARD_BACKGROUND'),
        _resource('color', kind: 'COLOR'),
        _resource('locked', member: 'PRO', available: false),
        _resource('hidden', member: 'PRO', available: false, preview: false),
        _resource('offline')..['status'] = 'OFFLINE',
      ];
      expect(
        albumResourceChoices(
          rows,
          kinds: {'BACKGROUND', 'COLOR'},
          scene: 'ALBUM_PAGE',
        ).map((r) => r['id']),
        ['page', 'color', 'locked'],
      );
      expect(
        albumResourceAvailable({'membership': 'PRO'}, plan: 'NORMAL'),
        isFalse,
      );
      expect(
        albumResourceAvailable({'membership': 'PRO'}, plan: 'PRO'),
        isTrue,
      );
    },
  );

  test('historical material snapshots win over changed or absent library resources', () {
    final original = _resource('theme');
    final background = albumResourceBackground(original);
    original['config'] = albumBackground(['#FF0000']);
    expect(albumResourceConfig(background, resources: [original])['colors'], [
      '#AABBCC',
    ]);
    expect(albumDecoration(background).color, const Color(0xFFAABBCC));
    final shelf = AlbumShelfData.fromJson({
      'items': [],
      'preferences': {
        'shelf_theme': 'theme',
        'shelf_snapshot': background['resource_snapshot'],
      },
    });
    expect(shelf.shelfSnapshot?['config']['colors'], ['#AABBCC']);
    final image = albumDecoration({
      'type': 'IMAGE',
      'colors': ['#FFFFFF'],
      'image_url': 'https://images.example/bg.webp',
    }).image!;
    expect((image.image as NetworkImage).url, 'https://images.example/bg.webp');
  });

  testWidgets(
    'locked PRO material gives a requirement message without inserting it',
    (tester) async {
      var inserted = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 110,
              height: 110,
              child: AlbumResourceTile(
                resource: _resource('PRO 背景', member: 'PRO', available: false),
                onSelected: () => inserted = true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('PRO 背景'));
      await tester.pump();
      expect(inserted, isFalse);
      expect(find.textContaining('此素材需要 PRO 权益'), findsOneWidget);
    },
  );

  testWidgets(
    'server colors and scene-specific backgrounds select a saved resource snapshot',
    (tester) async {
      AlbumJson? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: FanOsTheme.light,
          home: Scaffold(
            body: AlbumBackgroundPanel(
              original: albumBackground(),
              scene: 'ALBUM_PAGE',
              resources: [
                _resource('内页色', kind: 'COLOR'),
                _resource('封面专属', scene: 'ALBUM_COVER'),
              ],
              onClose: (value) => saved = value,
            ),
          ),
        ),
      );
      expect(find.text('封面专属'), findsNothing);
      await tester.tap(find.text('内页色'));
      await tester.pump();
      await tester.tap(find.text('完成'));
      expect(saved?['resource_id'], '内页色');
      expect(saved?['resource_snapshot']['config']['colors'], ['#AABBCC']);
    },
  );

  testWidgets(
    'cover-only material is not copied into the page carousel background',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockAlbumRepository();
      final album = await repo.create('素材适用场景', 'SINGLE', 'REALISTIC');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            albumRepositoryProvider.overrideWithValue(repo),
            albumDraftStoreProvider.overrideWithValue(_MemoryStore()),
            albumResourcesProvider.overrideWith(
              (ref) async => [_resource('封面专属', scene: 'ALBUM_COVER')],
            ),
          ],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: AlbumEditorPage(albumId: album.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('背景'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('封面专属'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlbumBackgroundPanel),
          matching: find.text('完成'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final saved = await repo.get(album.id);
      expect(saved.cover['background']['resource_id'], '封面专属');
      expect(saved.cardView['background']['resource_id'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline sticker uses its saved image, and unknown old stickers are not replaced by a star',
    (tester) async {
      final album = PhotocardAlbum({'id': 'a'});
      final e = <String, dynamic>{
        'id': 's',
        'type': 'STICKER',
        'content': 'custom',
        'rotation': 0,
        'resource_snapshot': {
          'id': 'custom',
          'name': 'saved',
          'kind': 'STICKER',
          'config': {'image_url': 'https://images.example/sticker.webp'},
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: AlbumElementWidget(
                element: e,
                album: album,
                canvasSize: const Size(300, 400),
                selected: false,
                resources: const [],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<FanImage>(find.byType(FanImage)).imageUrl,
        'https://images.example/sticker.webp',
      );
      e.remove('resource_snapshot');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: AlbumElementWidget(
                element: e,
                album: album,
                canvasSize: const Size(300, 400),
                selected: false,
                resources: const [],
              ),
            ),
          ),
        ),
      );
      expect(find.text('✦'), findsNothing);
      expect(find.byTooltip('原贴纸素材暂不可用'), findsOneWidget);
    },
  );

  testWidgets(
    'pending moderation disables repeat reviews and restoration does not claim publishing',
    (tester) async {
      final pending = PhotocardAlbum({
        'id': 'a',
        'is_owner': true,
        'moderation_status': 'OFFLINE',
        'review_status': 'PENDING',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlbumModerationBanner(album: pending, onRequestReview: () {}),
          ),
        ),
      );
      expect(find.text('已下架 · 复核中'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      final restored = PhotocardAlbum({
        'id': 'a',
        'is_owner': true,
        'moderation_status': 'NORMAL',
        'review_status': 'RESTORED',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AlbumModerationBanner(album: restored)),
        ),
      );
      expect(find.textContaining('尚未自动发布'), findsOneWidget);
    },
  );

  test(
    'review submits the saved revision and keeps album restricted',
    () async {
      final repo = _ReviewRepo();
      var album = await repo.create('Original', 'SINGLE', 'REALISTIC');
      album = await repo.save(
        album.edit((d) => d['moderation_status'] = 'RESTRICTED'),
      );
      final controller = AlbumEditorController(album.id, repo, _MemoryStore());
      addTearDown(controller.dispose);
      await controller.load();
      controller.edit((d) => d['name'] = 'Corrected');
      expect(await controller.requestReview(), isTrue);
      expect(repo.reviewedName, 'Corrected');
      expect(controller.album!.reviewStatus, 'PENDING');
      expect(controller.album!.isModerated, isTrue);
      await expectLater(
        repo.duplicate(controller.album!),
        throwsA(isA<ApiException>()),
      );
    },
  );

  testWidgets(
    'canceling source costs nothing; retry reuses ID and applying colors does not request again',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _ExtractionRepo();
      List<String>? selected;
      var quotaUpdates = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [albumRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: FanOsTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await showAlbumColorExtraction(
                      context,
                      quota: AlbumQuota.fromJson(_quotaJson()),
                      onQuotaChanged: (_) => quotaUpdates++,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(repo.requestIds, isEmpty);
      await tester.tap(find.text('选择小卡'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.requestIds, isEmpty);
      await tester.tap(find.text('选择小卡'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AlbumCardImage).first);
      await tester.pump();
      await tester.tap(find.text('已选择 1 张 · 用于取色'));
      await tester.pumpAndSettle();
      expect(repo.requestIds, isEmpty);
      await tester.tap(find.text('开始分析（消耗 1 次）'));
      await tester.pumpAndSettle();
      expect(find.text('网络暂时不可用，请重试'), findsOneWidget);
      expect(quotaUpdates, 0);
      await tester.tap(find.text('重试本次分析'));
      await tester.pumpAndSettle();
      expect(repo.requestIds.length, 2);
      expect(repo.requestIds.toSet(), hasLength(1));
      expect(quotaUpdates, 1);
      await tester.ensureVisible(find.text('#112233'));
      await tester.tap(find.text('#112233'));
      await tester.pumpAndSettle();
      expect(selected, ['#112233']);
      expect(repo.requestIds.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  test('color requests send bytes or a card, preserve request ID on retries, and parse quota', () async {
    final requests = <FormData>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, '/albums/color-extractions');
          requests.add(options.data as FormData);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'code': 0,
                'data': {
                  'request_id': 'request-1',
                  'colors': ['#112233', '#445566'],
                  'quota': _quotaJson(),
                },
              },
            ),
          );
        },
      ),
    );
    final repo = ApiAlbumRepository(ApiClient(dio: dio));
    final result = await repo.extractColors(
      requestId: 'request-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'photo.png',
    );
    await repo.extractColors(
      requestId: 'request-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'photo.png',
    );
    await repo.extractColors(requestId: 'request-2', cardId: 'card-a');
    expect(
      requests.take(2).map((r) => Map.fromEntries(r.fields)['request_id']),
      ['request-1', 'request-1'],
    );
    expect(requests.first.files.single.value.filename, 'photo.png');
    expect(
      Map.fromEntries(requests.first.fields).containsKey('card_id'),
      isFalse,
    );
    expect(requests.last.files, isEmpty);
    expect(Map.fromEntries(requests.last.fields)['card_id'], 'card-a');
    expect(result.colors, ['#112233', '#445566']);
    expect(result.quota.colorExtraction!.dailyRemaining, 2);
    expect(
      RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(newAlbumColorRequestId()),
      isTrue,
    );
  });
}
