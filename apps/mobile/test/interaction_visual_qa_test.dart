// Optional local render check. Produces Flutter-rendered PNGs, not mockup images.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/demo_catalog.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/scan_detection_repository.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_list_page.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:fan_os/features/profile/presentation/edit_profile_page.dart';
import 'package:fan_os/features/onboarding/presentation/favorite_setup_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/scan/presentation/scan_result_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_entity_detail_page.dart';
import 'package:fan_os/features/scan/presentation/scan_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render local interaction QA snapshots', (tester) async {
    await tester.runAsync(() async {
      final data = ByteData.sublistView(
        await File('/System/Library/Fonts/STHeiti Light.ttc').readAsBytes(),
      );
      for (final family in [
        'FanQa',
        'Ahem',
        'Roboto',
        'PingFang SC',
        'Helvetica Neue',
        'Roboto_500',
        '.SF UI Text',
        '.SF UI Display',
      ]) {
        final font = FontLoader(family)..addFont(Future.value(data));
        await font.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Directory(
      const String.fromEnvironment(
        'QA_OUTPUT_DIR',
        defaultValue: '../../output/mobile-20261013/qa',
      ),
    )..createSync(recursive: true);
    final background = '${output.absolute.path}/background-fixture.png';
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 600, 480),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            const Offset(600, 480),
            [const Color(0xFFDE9C53), const Color(0xFF7368BC)],
          ),
      );
      canvas.drawCircle(
        const Offset(180, 140),
        115,
        Paint()..color = const Color(0xFFFFE6B3),
      );
      canvas.drawRect(
        const Rect.fromLTWH(400, 0, 60, 480),
        Paint()..color = const Color(0xFF3E6177),
      );
      final picture = recorder.endRecording();
      final img = await picture.toImage(600, 480);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(background).writeAsBytes(bytes!.buffer.asUint8List());
      PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(File(background)),
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: img.clone())),
        ),
      );
      img.dispose();
      picture.dispose();
    });
    Future<void> capture(
      String name,
      Widget page, {
      bool error = false,
      bool guest = false,
      bool loggedIn = false,
      CatalogBundle? catalog,
      Future<void> Function()? beforeCapture,
    }) async {
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(_Catalog(error, catalog)),
        ],
      );
      if (guest) container.read(sessionProvider.notifier).continueAsGuest();
      if (loggedIn) {
        await tester.runAsync(
          () =>
              container.read(sessionProvider.notifier).login(LoginMethod.phone),
        );
        container
            .read(sessionProvider.notifier)
            .updateProfile(
              displayName: 'Fan OS 运营',
              bio: '',
              syncRemote: false,
            );
        await container
            .read(sessionProvider.notifier)
            .saveProfileImage('background', background);
        container.read(favoritesProvider.notifier).hydrate({
          'idol-aria',
          'idol-lin',
        }, 'idol-lin');
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FanOsTheme.light.copyWith(
              textTheme: FanOsTheme.light.textTheme.apply(fontFamily: 'FanQa'),
              filledButtonTheme: FilledButtonThemeData(
                style: FanOsTheme.light.filledButtonTheme.style!.copyWith(
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'FanQa',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: FanOsTheme.light.outlinedButtonTheme.style!.copyWith(
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'FanQa',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: FanOsTheme.light.textButtonTheme.style!.copyWith(
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(
                      fontFamily: 'FanQa',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              chipTheme: FanOsTheme.light.chipTheme.copyWith(
                labelStyle: const TextStyle(
                  fontFamily: 'FanQa',
                  fontSize: 12,
                  color: FanColors.textSecondary,
                ),
              ),
            ),
            home: RepaintBoundary(key: key, child: page),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await beforeCapture?.call();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }

    await capture(
      'popular-group-photo-mask',
      const CatalogPage(),
      catalog: CatalogBundle(
        idols: [],
        cards: [],
        groups: [
          FanGroup.fromJson({
            'id': 'photo-example',
            'name': 'SEVENTEEN',
            'name_ko': '세븐틴',
            'image_url': background,
            'member_count': 13,
          }),
          FanGroup.fromJson({'id': 'placeholder', 'name': 'ATEEZ'}),
        ],
      ),
      beforeCapture: () async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('popular-group-photo-example')),
        );
        await tester.pumpAndSettle();
      },
    );
    await capture(
      'polish-profile',
      const ProfilePage(),
      loggedIn: true,
      catalog: DemoCatalog.bundle,
    );
    await capture(
      'polish-edit-profile',
      const EditProfilePage(),
      loggedIn: true,
      catalog: DemoCatalog.bundle,
    );
    await capture(
      'polish-favorites',
      const FavoriteSetupPage(),
      loggedIn: true,
      catalog: DemoCatalog.bundle,
    );
    await capture(
      'polish-group',
      const GroupDetailPage(groupId: 'group-lumina'),
      catalog: DemoCatalog.bundle,
    );
    await capture(
      'polish-album',
      CatalogEntityDetailPage(
        type: CatalogEntityDetailType.album,
        entityId: DemoCatalog.albums.first.id,
      ),
      catalog: DemoCatalog.bundle,
    );
    await capture(
      'polish-idol',
      const IdolDetailPage(idolId: 'idol-aria'),
      catalog: DemoCatalog.bundle,
    );
    await capture(
      'polish-scan',
      ScanResultPage(
        session: ScanSession(
          id: 'qa',
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
        ),
      ),
      loggedIn: true,
      catalog: DemoCatalog.bundle,
      beforeCapture: () async {
        await tester.tap(find.byKey(const Key('scan-select-all')));
        await tester.pumpAndSettle();
      },
    );
    await capture('home-empty', const HomePage(), guest: true);
    await capture('catalog-error', const CatalogPage(), error: true);
    final catalog = CatalogBundle(
      groups: [
        FanGroup.fromJson({
          'id': 'group-lumina',
          'name': 'SEVENTEEN',
          'name_ko': '세븐틴',
          'company': 'PLEDIS Entertainment Company With A Long Name',
          'member_ids': List.generate(13, (i) => '$i'),
        }),
        ...DemoCatalog.groups.skip(1),
      ],
      idols: DemoCatalog.idols,
      cards: DemoCatalog.cards,
      albums: DemoCatalog.albums,
    );
    await capture(
      'catalog-group-statistics',
      const CatalogPage(),
      catalog: catalog,
      beforeCapture: () async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('group-stats-group-lumina')),
        );
        await tester.pumpAndSettle();
      },
    );
    await capture(
      'all-groups-statistics',
      const CatalogListPage(type: CatalogListType.groups),
      catalog: catalog,
    );
    final sample = DemoCatalog.cards.first;
    final groupCard = CollectibleCard(
      id: 'group-photo',
      title: '',
      idolId: '',
      idolName: '团体小卡',
      isGroupCard: true,
      groupId: sample.groupId,
      groupName: sample.groupName,
      source: sample.source,
      cardType: sample.cardType,
      version: sample.version,
      releaseDate: '',
      region: '',
      colorStart: sample.colorStart,
      colorEnd: sample.colorEnd,
    );
    await capture(
      'card-captions',
      Scaffold(
        appBar: AppBar(title: const Text('小卡文字展示回归')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in [
                (sample, CardTileCaption.idol),
                (sample, CardTileCaption.group),
                (groupCard, CardTileCaption.group),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CollectibleCardTile(
                      card: entry.$1,
                      caption: entry.$2,
                      sourceLabel: DemoCatalog.bundle.cardSourceLabel(entry.$1),
                      versionLabel: DemoCatalog.bundle.cardVersionLabel(
                        entry.$1,
                      ),
                      compact: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final detection = await MockScanDetectionRepository().detect(null);
    await capture(
      'scan-no-person',
      Scaffold(
        backgroundColor: const Color(0xFF24232C),
        appBar: AppBar(title: const Text('请选择要扫描的小卡')),
        body: ScanSelection(
          detection: const ScanDetection(sessionId: 'empty', regions: []),
          imageSize: const Size(3, 4),
          onScan: (_) async {},
          onRetake: () {},
        ),
      ),
    );
    await capture(
      'scan-selection',
      Scaffold(
        backgroundColor: const Color(0xFF24232C),
        appBar: AppBar(title: const Text('请选择要扫描的小卡')),
        body: ScanSelection(
          detection: detection,
          imageSize: const Size(3, 4),
          onRetake: () {},
          onScan: (_) async {},
        ),
      ),
    );
  }, skip: !const bool.fromEnvironment('RUN_INTERACTION_VISUAL_QA'));
}

class _Catalog implements CatalogRepository {
  _Catalog(this.error, this.catalog);
  final bool error;
  final CatalogBundle? catalog;
  @override
  Future<CatalogBundle> fetchCatalog() async {
    if (error) throw StateError('Offline fixture');
    return catalog ?? const CatalogBundle(idols: [], groups: [], cards: []);
  }
}
