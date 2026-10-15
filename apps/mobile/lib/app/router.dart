import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/config/feature_flags.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/features/albums/presentation/album_editor_page.dart';
import 'package:fan_os/features/albums/presentation/album_shelf_page.dart';
import 'package:fan_os/features/albums/presentation/album_viewer_page.dart';
import 'package:fan_os/features/catalog/presentation/card_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/card_gallery_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_entity_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/catalog_list_page.dart';
import 'package:fan_os/features/catalog/presentation/group_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/idol_detail_page.dart';
import 'package:fan_os/features/catalog/presentation/search_page.dart';
import 'package:fan_os/features/collection/presentation/collection_page.dart';
import 'package:fan_os/features/collection/presentation/library_search_page.dart';
import 'package:fan_os/features/daily_card/presentation/daily_card_page.dart';
import 'package:fan_os/features/feed/presentation/feed_page.dart';
import 'package:fan_os/features/feed/presentation/feed_post_detail_page.dart';
import 'package:fan_os/features/home/presentation/home_page.dart';
import 'package:fan_os/features/notification/presentation/notifications_page.dart';
import 'package:fan_os/features/onboarding/presentation/favorite_setup_page.dart';
import 'package:fan_os/features/onboarding/presentation/launch_page.dart';
import 'package:fan_os/features/onboarding/presentation/login_page.dart';
import 'package:fan_os/features/onboarding/presentation/privacy_page.dart';
import 'package:fan_os/features/profile/presentation/edit_profile_page.dart';
import 'package:fan_os/features/profile/presentation/profile_page.dart';
import 'package:fan_os/features/profile/presentation/profile_support_pages.dart';
import 'package:fan_os/features/scan/presentation/scan_page.dart';
import 'package:fan_os/features/scan/presentation/scan_feedback_page.dart';
import 'package:fan_os/features/feedback/feedback_center.dart';
import 'package:fan_os/features/feedback/correction_page.dart';
import 'package:fan_os/features/feedback/missing_card_page.dart';
import 'package:fan_os/features/scan/presentation/catalog_missing_feedback_page.dart';
import 'package:fan_os/features/scan/presentation/scan_result_page.dart';
import 'package:fan_os/features/shell/presentation/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
const _initialLocation = String.fromEnvironment(
  'INITIAL_ROUTE',
  defaultValue: '/',
);

final GoRouter fanOsRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: _initialLocation,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const LaunchPage()),
    GoRoute(
      path: '/collection/search',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LibrarySearchPage(),
    ),
    GoRoute(path: '/privacy', builder: (context, state) => const PrivacyPage()),
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/onboarding/favorites',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => FavoriteSetupPage(
        isOnboarding: state.uri.queryParameters['welcome'] == '1',
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/catalog',
              builder: (context, state) => const CatalogPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scan',
              builder: (context, state) => const ScanPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/collection',
              builder: (context, state) => const CollectionPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfilePage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/digital-albums',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          AlbumShelfPage(userId: state.uri.queryParameters['user']),
    ),
    GoRoute(
      path: '/catalog/feedback',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CatalogMissingFeedbackPage(
        args: state.extra is CatalogMissingFeedbackRouteArgs
            ? state.extra as CatalogMissingFeedbackRouteArgs
            : null,
      ),
    ),
    GoRoute(
      path: '/digital-albums/new',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AlbumCreatePage(),
    ),
    GoRoute(
      path: '/digital-albums/:albumId/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => AlbumEditorPage(
        albumId: state.pathParameters['albumId']!,
        initialPanel: state.uri.queryParameters['panel'],
      ),
    ),
    GoRoute(
      path: '/digital-albums/:albumId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          AlbumViewerPage(albumId: state.pathParameters['albumId']!),
    ),
    GoRoute(
      path: '/daily-card',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DailyCardPage(),
    ),
    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          SearchPage(initialType: state.uri.queryParameters['type']),
    ),
    GoRoute(
      path: '/group/:groupId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          GroupDetailPage(groupId: state.pathParameters['groupId']!),
    ),
    GoRoute(
      path: '/idol/:idolId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          IdolDetailPage(idolId: state.pathParameters['idolId']!),
    ),
    GoRoute(
      path: '/cards',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CardGalleryPage(
        groupId: state.uri.queryParameters['group'],
        idolId: state.uri.queryParameters['idol'],
      ),
    ),
    GoRoute(
      path: '/catalog/groups',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          const CatalogListPage(type: CatalogListType.groups),
    ),
    GoRoute(
      path: '/catalog/idols',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          const CatalogListPage(type: CatalogListType.idols),
    ),
    GoRoute(
      path: '/catalog/albums',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          const CatalogListPage(type: CatalogListType.albums),
    ),
    GoRoute(
      path: '/catalog/events',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          const CatalogListPage(type: CatalogListType.events),
    ),
    GoRoute(
      path: '/catalog/others',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          const CatalogListPage(type: CatalogListType.others),
    ),
    GoRoute(
      path: '/album/:albumId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CatalogEntityDetailPage(
        type: CatalogEntityDetailType.album,
        entityId: state.pathParameters['albumId']!,
      ),
    ),
    GoRoute(
      path: '/event/:eventId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CatalogEntityDetailPage(
        type: CatalogEntityDetailType.event,
        entityId: state.pathParameters['eventId']!,
      ),
    ),
    GoRoute(
      path: '/other/:othersId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CatalogEntityDetailPage(
        type: CatalogEntityDetailType.others,
        entityId: state.pathParameters['othersId']!,
      ),
    ),
    GoRoute(
      path: '/card/:cardId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          CardDetailPage(cardId: state.pathParameters['cardId']!),
    ),
    GoRoute(
      path: '/scan-result',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ScanResultPage(
        key: ValueKey(
          state.extra is ScanSession ? (state.extra! as ScanSession).id : null,
        ),
        session: state.extra is ScanSession
            ? state.extra! as ScanSession
            : null,
      ),
    ),
    GoRoute(
      path: '/scan-feedback',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => MissingCardFeedbackPage(
        args: state.extra is ScanFeedbackRouteArgs
            ? state.extra! as ScanFeedbackRouteArgs
            : null,
      ),
    ),
    GoRoute(
      path: '/scan-feedback-history',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          const FeedbackCenterPage(initialKind: 'MISSING_CARD'),
    ),
    GoRoute(
      path: '/feedback',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          FeedbackCenterPage(initialKind: state.uri.queryParameters['kind']),
    ),
    GoRoute(
      path: '/feedback/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          FeedbackDetailPage(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/catalog-correction',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CorrectionPage(
        entityType: state.uri.queryParameters['type'] ?? 'cards',
        entityId: state.uri.queryParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const NotificationsPage(),
    ),
    GoRoute(
      path: '/feed',
      redirect: (context, state) => idolFeedEnabled ? null : '/home',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FeedPage(),
    ),
    GoRoute(
      path: '/feed/post/:postId',
      redirect: (context, state) => idolFeedEnabled ? null : '/home',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => FeedPostDetailPage(
        postId: state.pathParameters['postId']!,
        initialPost: state.extra is SocialFeedPost
            ? state.extra! as SocialFeedPost
            : null,
      ),
    ),
    GoRoute(
      path: '/profile/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const EditProfilePage(),
    ),
    GoRoute(
      path: '/profile/level',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ProfileLevelPage(
        payload: state.extra is Map<String, Object>
            ? state.extra! as Map<String, Object>
            : null,
      ),
    ),
    GoRoute(
      path: '/profile/relations',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ProfileRelationsPage(
        type: state.uri.queryParameters['type'] ?? 'following',
        userId: state.uri.queryParameters['user'] ?? 'current-user',
      ),
    ),
    GoRoute(
      path: '/user/:userId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          ProfilePage(userId: state.pathParameters['userId']!),
    ),
  ],
);
