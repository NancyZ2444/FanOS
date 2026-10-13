import 'dart:convert';
import 'dart:io';

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/data/repositories.dart';
import 'package:fan_os/core/data/social_feed_repository.dart';
import 'package:fan_os/core/data/user_data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _runIntegration = bool.fromEnvironment(
  'RUN_BACKEND_INTEGRATION',
  defaultValue: false,
);
const _scanTestImage = String.fromEnvironment('SCAN_TEST_IMAGE_PATH');

void main() {
  test('Flutter repositories complete a real Fan OS API flow', () async {
    final client = ApiClient();
    await ApiAuthRepository(client)
        .login(LoginMethod.phone, phone: '13800000000', code: '123456');

    final catalog = await ApiCatalogRepository(client).fetchCatalog();
    expect(catalog.groups, hasLength(3));
    expect(catalog.idols, hasLength(6));
    expect(catalog.cards.length, greaterThanOrEqualTo(7));
    expect(catalog.albums, hasLength(4));
    expect(catalog.events, hasLength(5));
    expect(catalog.others, hasLength(3));

    final search = await client.getData(
      '/catalog/search',
      query: {'q': 'Starlit'},
    ) as Map<String, dynamic>;
    expect(search['albums'], isNotEmpty);
    expect(search['cards'], isNotEmpty);

    final profile = await client.getData('/me/profile') as Map<String, dynamic>;
    expect(profile['id'], 'current-user');

    final userData = ApiUserDataRepository(client);
    final account = await userData.fetchAccountSnapshot();
    expect(account.displayName, isNotEmpty);
    expect(account.favoriteIdolIds, isNotEmpty);
    expect(account.albums.length, greaterThanOrEqualTo(2));
    await userData.updateProfile({'bio': 'Flutter 真接口联调账号'});
    await userData.setWishlist('card-aria-01', true);
    await userData.setOwnedQuantity('card-lin-01', 1);

    try {
      final drawn = await ApiDailyCardRepository(client)
          .draw(drawnCardIds: const [], favoriteIdolIds: const []);
      expect(catalog.cards.map((card) => card.id), contains(drawn.id));
    } on ApiException catch (error) {
      expect(error.code, 'DAILY_CARD_LIMIT_REACHED');
    }

    final feed = await ApiSocialFeedRepository(client).fetchFeed(limit: 20);
    expect(feed.posts, hasLength(20));
    expect(feed.nextCursor, '20');

    final postId = feed.posts.first.id;
    final comment = await userData.createComment(postId, 'Flutter API 联调评论');
    expect(comment.content, 'Flutter API 联调评论');
    await userData.setCommentLiked(comment.id, true);
    final comments = await userData.fetchComments(postId);
    expect(comments.map((item) => item.id), contains(comment.id));
    await userData.reportComment(comment.id);
    await userData.deleteComment(comment.id);

    final temp = await Directory.systemTemp.createTemp(
      'fan-os-backend-contract-',
    );
    try {
      final image = File('${temp.path}/card.png');
      await image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      final repository = ApiScanRepository(client);
      final status =
          await client.getData('/scan/status') as Map<String, dynamic>;
      if (status['available'] != true) {
        await expectLater(
          repository.recognize(localImagePath: image.path),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'SCAN_INDEX_UNAVAILABLE',
            ),
          ),
        );
        expect(
          _scanTestImage,
          isEmpty,
          reason: 'Import an official card index before testing a real image',
        );
      } else {
        // A 1 px blank image must never receive fabricated demo candidates.
        final unknown = await repository.recognize(localImagePath: image.path);
        expect(unknown.detectedCards, isNotEmpty);
        expect(
          unknown.detectedCards.every((card) => card.candidates.isEmpty),
          isTrue,
        );
        if (_scanTestImage.isNotEmpty) {
          final scan = await repository.recognize(
            localImagePath: _scanTestImage,
          );
          final matched = scan.detectedCards.where(
            (card) => card.candidates.isNotEmpty,
          );
          expect(matched, isNotEmpty);
          final confirmations = matched
              .map(
                (card) => ScanConfirmation(
                  detectedCardId: card.id,
                  cardId: card.candidates.first.card.id,
                ),
              )
              .toList();
          final quantities = await repository.confirm(scan.id, confirmations);
          expect(quantities, isNotEmpty);
          expect(await repository.confirm(scan.id, confirmations), quantities);
        }
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }, skip: _runIntegration ? false : 'requires the local Fan OS API');
}
