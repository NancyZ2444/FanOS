import 'package:fan_os/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feedback_data.dart';

/// Only the server's adopted user contributions have a visible attribution.
/// Editorial creation and absent credits render no label or reserved space.
class CatalogContributors extends ConsumerWidget {
  const CatalogContributors({
    required this.kind,
    required this.entityId,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    super.key,
  });

  final String kind;
  final String entityId;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = catalogCreditsProvider((kind: kind, id: entityId));
    return ref
        .watch(provider)
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Padding(
            padding: padding,
            child: TextButton(
              onPressed: () => ref.invalidate(provider),
              child: const Text('来源信息加载失败，点击重试'),
            ),
          ),
          data: (items) {
            final contributors = items
                .where(
                  (item) =>
                      item['source_type'] == 'USER_SUBMITTED' &&
                      '${item['name'] ?? ''}'.trim().isNotEmpty,
                )
                .toList();
            if (contributors.isEmpty) return const SizedBox.shrink();
            return Padding(
              key: ValueKey('catalog-contributors-$kind-$entityId'),
              padding: padding,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '贡献来源：',
                    style: TextStyle(
                      fontSize: 13,
                      color: FanColors.textSecondary,
                    ),
                  ),
                  for (final item in contributors)
                    if (item['profile_available'] == true &&
                        item['user_id'] != null)
                      TextButton(
                        onPressed: () =>
                            context.push('/user/${item['user_id']}'),
                        style: TextButton.styleFrom(
                          foregroundColor: FanColors.ink,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          textStyle: const TextStyle(fontSize: 14),
                        ),
                        child: Text('${item['name']}'),
                      )
                    else
                      Text(
                        '${item['name']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: FanColors.ink,
                        ),
                      ),
                ],
              ),
            );
          },
        );
  }
}
