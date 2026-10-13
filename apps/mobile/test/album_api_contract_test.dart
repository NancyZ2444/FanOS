import 'package:dio/dio.dart';
import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/features/albums/data/album_models.dart';
import 'package:fan_os/features/albums/data/album_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const enabled = bool.fromEnvironment('RUN_ALBUM_API_CONTRACT');
const endpoint = String.fromEnvironment(
  'ALBUM_API_TEST_URL',
  defaultValue: 'http://127.0.0.1:18001/api/v1',
);

void main() {
  test(
    'Flutter digital album repository talks to isolated real FastAPI',
    () async {
      final client = ApiClient(dio: Dio(BaseOptions(baseUrl: endpoint)));
      final auth = await client.postData(
        '/auth/login',
        data: {'method': 'phone', 'phone': '13800000000', 'code': '123456'},
      );
      client.setAccessToken(auth['access_token'] as String);
      final repo = ApiAlbumRepository(client);
      final visitor = ApiClient(dio: Dio(BaseOptions(baseUrl: endpoint)));
      final admin = ApiClient(dio: Dio(BaseOptions(baseUrl: endpoint)));
      final adminAuth = await admin.postData(
        '/auth/login',
        data: {'method': 'phone', 'phone': '13900000000', 'code': '123456'},
      );
      admin.setAccessToken(adminAuth['access_token'] as String);
      final visitorRepo = ApiAlbumRepository(visitor),
          adminRepo = ApiAlbumRepository(admin);
      var album = await repo.create(
        'Flutter API integration',
        'DOUBLE',
        'REALISTIC',
      );
      addTearDown(() async {
        await repo.delete(await repo.get(album.id));
      });
      expect(() => visitorRepo.get(album.id), throwsA(isA<ApiException>()));
      final first = blankAlbumPage(3);
      (first['slots'] as List)[0]['card_id'] = 'card-aria-01';
      (first['slots'] as List)[1]['card_id'] = 'card-aria-01';
      (first['slots'] as List)[2]['card_id'] = 'card-lin-01';
      album = await repo.save(
        album.edit((d) {
          d['pages'] = [first];
          d['visibility'] = 'PUBLIC';
        }),
      );
      expect(album.cardCount, 3);
      expect(album.card('card-aria-01'), isNotNull);
      final slotIds = album.orderedSlotIds;
      album = await repo.save(
        album.edit(
          (d) => d['card_view'] = {
            'card_order': slotIds.reversed.toList(),
            'order_customized': true,
            'featured_slot_id': slotIds.last,
            'background': albumBackground(),
          },
        ),
      );
      expect(album.orderedSlotIds.first, slotIds.last);
      final oldVersion = album;
      album = await repo.publish(album);
      expect(() => repo.save(oldVersion), throwsA(isA<ApiException>()));
      expect((await visitorRepo.get(album.id)).cardCount, 3);
      album = await repo.save(
        album.edit((d) => d['name'] = 'Unpublished edit'),
      );
      expect((await visitorRepo.get(album.id)).name, 'Flutter API integration');
      await adminRepo.react(album.id, 'favorite', true);
      await adminRepo.react(album.id, 'like', true);
      expect(
        (await adminRepo.list(favorites: true)).albums.map((a) => a.id),
        contains(album.id),
      );
      expect(
        (await repo.cardAssets(['card-aria-01']))['card-aria-01']['available'],
        isTrue,
      );
      final copied = await repo.duplicate(album);
      addTearDown(() => repo.delete(copied));
      expect(
        copied.orderedSlotIds.toSet().intersection(slotIds.toSet()),
        isEmpty,
      );
      expect(copied.isPublic, isFalse);
      await repo.preferences('natural-wood', 'LIST');
      final shelf = await repo.list(q: 'Unpublished');
      expect(shelf.albums.length, 2);
      expect(shelf.theme, 'natural-wood');
      expect(shelf.viewMode, 'LIST');
      expect((await repo.quota()).maxPages, 10);
      await adminRepo.react(album.id, 'favorite', false);
      await adminRepo.react(album.id, 'like', false);
    },
    skip: enabled ? false : 'requires the disposable API on port 18001; never run against production',
  );
}
