import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:fan_os/features/albums/data/album_resources.dart';
import 'package:flutter_test/flutter_test.dart';

const enabled = bool.fromEnvironment('RUN_ALBUM_API_CONTRACT');
const endpoint = String.fromEnvironment(
  'ALBUM_API_TEST_URL',
  defaultValue: 'http://127.0.0.1:18001/api/v1',
);

void main() {
  test(
    'P0 App repository integrates with material permissions, historical snapshots, moderation and color quota',
    () async {
      final owner = ApiClient(dio: Dio(BaseOptions(baseUrl: endpoint)));
      final admin = ApiClient(dio: Dio(BaseOptions(baseUrl: endpoint)));
      final visitor = ApiAlbumRepository(
        ApiClient(dio: Dio(BaseOptions(baseUrl: endpoint))),
      );
      final uniquePhone =
          '138${(DateTime.now().microsecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';
      for (final entry in [(owner, uniquePhone), (admin, '13900000000')]) {
        final auth = await entry.$1.postData(
          '/auth/login',
          data: {'method': 'phone', 'phone': entry.$2, 'code': '666666'},
        );
        entry.$1.setAccessToken(auth['access_token'] as String);
      }
      final repo = ApiAlbumRepository(owner);
      final profile = await owner.getData('/me/profile') as AlbumJson;
      final userId = profile['id'] as String;
      await admin.putData(
        '/admin/console/album-entitlements/$userId',
        data: {'plan': 'NORMAL'},
      );
      addTearDown(
        () => admin.putData(
          '/admin/console/album-entitlements/$userId',
          data: {'plan': 'NORMAL'},
        ),
      );
      final initialQuota = await repo.quota();
      expect(initialQuota.colorExtraction!.dailyLimit, 3);
      expect(initialQuota.colorExtraction!.monthlyLimit, 20);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final key = DateTime.now().microsecondsSinceEpoch.toString();
      await expectLater(
        repo.extractColors(
          requestId: 'invalid-$key',
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'bad.png',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        (await repo.quota()).colorExtraction!.dailyUsed,
        initialQuota.colorExtraction!.dailyUsed,
      );
      final palette = await repo.extractColors(
        requestId: 'valid-$key',
        bytes: bytes,
        fileName: 'color.png',
      );
      final retry = await repo.extractColors(
        requestId: 'valid-$key',
        bytes: bytes,
        fileName: 'color.png',
      );
      expect(palette.colors, isNotEmpty);
      expect(retry.colors, palette.colors);
      expect(
        retry.quota.colorExtraction!.dailyUsed,
        initialQuota.colorExtraction!.dailyUsed + 1,
      );
      final upload = await admin.postData(
        '/admin/console/album-resources/upload',
        data: FormData.fromMap({
          'kind': 'STICKER',
          'file': MultipartFile.fromBytes(bytes, filename: 'sticker.png'),
        }),
      ) as AlbumJson;
      final url = upload['url'] as String;
      final resource = <String, dynamic>{
        'id': 'pro-sticker-$key',
        'name': 'P0 测试贴纸',
        'kind': 'STICKER',
        'status': 'PUBLISHED',
        'scene': 'COVER',
        'membership': 'PRO',
        'locked_preview': true,
        'config': {'image_url': url},
      };
      await admin.postData('/admin/console/album-resources', data: resource);
      addTearDown(
        () => admin.putData(
          '/admin/console/album-resources/${resource['id']}',
          data: {...resource, 'status': 'OFFLINE'},
        ),
      );
      final imageBackground = <String, dynamic>{
        'id': 'background-$key',
        'name': '封面图片',
        'kind': 'BACKGROUND',
        'status': 'PUBLISHED',
        'scene': 'COVER',
        'config': {
          'type': 'IMAGE',
          'colors': ['#FFFFFF'],
          'angle': 45,
          'image_url': url,
        },
      };
      final imageShelf = <String, dynamic>{
        'id': 'shelf-$key',
        'name': '图片书架',
        'kind': 'SHELF',
        'status': 'PUBLISHED',
        'config': {
          'colors': ['#FFFFFF', '#F5F5F5'],
          'ledge': '#EEEEEE',
          'image_url': url,
        },
      };
      for (final material in [imageBackground, imageShelf]) {
        await admin.postData('/admin/console/album-resources', data: material);
        addTearDown(
          () => admin.putData(
            '/admin/console/album-resources/${material['id']}',
            data: {...material, 'status': 'OFFLINE'},
          ),
        );
      }
      await repo.preferences(imageShelf['id'] as String, 'SHELF');
      expect((await repo.list()).shelfSnapshot?['config']['image_url'], url);
      final available = (await repo.resources()).firstWhere(
        (r) => r['id'] == resource['id'],
      );
      expect(available['available'], isFalse);
      var album = await repo.create(
        'P0 Flutter contract',
        'SINGLE',
        'REALISTIC',
      );
      addTearDown(() async {
        await repo.delete(await repo.get(album.id));
      });
      final sticker = <String, dynamic>{
        'id': 'sticker-one',
        'type': 'STICKER',
        'content': resource['id'],
        'x': .1,
        'y': .1,
        'width': .3,
        'height': .3,
        'rotation': 0,
        'z_index': 1,
        'resource_snapshot': albumResourceSnapshot(resource),
      };
      PhotocardAlbum withSticker() =>
          album.edit((d) => (d['cover'] as AlbumJson)['elements'] = [sticker]);
      await expectLater(repo.save(withSticker()), throwsA(isA<ApiException>()));
      await admin.putData(
        '/admin/console/album-entitlements/$userId',
        data: {'plan': 'PRO'},
      );
      expect((await repo.quota()).colorExtraction!.dailyLimit, 30);
      expect(
        (await repo.resources()).firstWhere(
          (r) => r['id'] == resource['id'],
        )['available'],
        isTrue,
      );
      album = await repo.save(
        withSticker().edit(
          (d) => d['cover']['background'] = albumResourceBackground(
            imageBackground,
          ),
        ),
      );
      expect(
        (album.cover['elements'] as List)
            .first['resource_snapshot']['config']['image_url'],
        url,
      );
      await admin.putData(
        '/admin/console/album-resources/${resource['id']}',
        data: {...resource, 'status': 'OFFLINE'},
      );
      await admin.putData(
        '/admin/console/album-entitlements/$userId',
        data: {'plan': 'NORMAL'},
      );
      for (final material in [imageBackground, imageShelf]) {
        await admin.putData(
          '/admin/console/album-resources/${material['id']}',
          data: {...material, 'status': 'OFFLINE'},
        );
      }
      expect(
        (await repo.resources()).any(
          (r) => [imageBackground['id'], imageShelf['id']].contains(r['id']),
        ),
        isFalse,
      );
      expect((await repo.list()).shelfSnapshot?['config']['image_url'], url);
      await repo.preferences(imageShelf['id'] as String, 'LIST');
      expect((await repo.list()).shelfSnapshot?['config']['image_url'], url);
      album = await repo.save(
        album.edit((d) => (d['cover']['elements'] as List).first['x'] = .2),
      );
      expect(
        (album.cover['elements'] as List)
            .first['resource_snapshot']['config']['image_url'],
        url,
      );
      expect(
        album.cover['background']['resource_snapshot']['config']['image_url'],
        url,
      );
      await expectLater(repo.duplicate(album), throwsA(isA<ApiException>()));
      await expectLater(
        repo.save(
          album.edit(
            (d) => (d['cover']['elements'] as List).add({
              ...sticker,
              'id': 'sticker-two',
            }),
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      album = await repo.save(album.edit((d) => d['visibility'] = 'PUBLIC'));
      album = await repo.publish(album);
      expect((await visitor.get(album.id)).name, 'P0 Flutter contract');
      await admin.putData(
        '/admin/console/digital-albums/${album.id}/moderation',
        data: {'status': 'OFFLINE', 'reason_code': 'IMAGE', 'reason': '测试图片处理'},
      );
      album = await repo.get(album.id);
      expect(album.moderationStatus, 'OFFLINE');
      await expectLater(visitor.get(album.id), throwsA(isA<ApiException>()));
      await expectLater(repo.duplicate(album), throwsA(isA<ApiException>()));
      album = await repo.save(album.edit((d) => d['name'] = '已修改的待复核作品'));
      album = await repo.requestReview(album);
      expect(album.reviewStatus, 'PENDING');
      final detail = await admin.getData(
        '/admin/console/digital-albums/${album.id}',
        query: {'preview': 'review'},
      ) as AlbumJson;
      expect(detail['name'], '已修改的待复核作品');
      await admin.putData(
        '/admin/console/digital-albums/${album.id}/moderation',
        data: {
          'status': 'NORMAL',
          'reason_code': 'OTHER',
          'reason': '复核恢复',
          'review_id': detail['review_request']['id'],
        },
      );
      album = await repo.get(album.id);
      expect(album.reviewStatus, 'RESTORED');
      expect(album.isModerated, isFalse);
      await expectLater(visitor.get(album.id), throwsA(isA<ApiException>()));
      album = await repo.publish(album);
      expect(album.reviewStatus, 'NONE');
      expect((await visitor.get(album.id)).name, '已修改的待复核作品');
    },
    skip: enabled
        ? false
        : 'Only run on disposable local API; never production.',
  );
}
