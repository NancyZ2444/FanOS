import 'dart:math' as math;
import 'dart:io';

import 'package:fan_os/core/api/api_client.dart';
import 'package:fan_os/core/widgets/portrait_image.dart';

import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FanEntityName extends ConsumerWidget {
  const FanEntityName({
    required this.kind,
    required this.id,
    required this.officialName,
    this.suffix = '',
    this.style,
    this.maxLines,
    this.overflow,
    super.key,
  });
  final String kind, id, officialName, suffix;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    '${ref.watch(namePreferencesProvider).display(kind, id, officialName)}$suffix',
    style: style,
    maxLines: maxLines,
    overflow: overflow,
  );
}

class FanContent extends StatelessWidget {
  const FanContent({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class FanWordmark extends StatelessWidget {
  const FanWordmark({super.key, this.light = false, this.fontSize = 25});

  final bool light;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Fan OS',
      style: TextStyle(
        color: light ? Colors.white : FanColors.ink,
        fontFamily: 'Helvetica Neue',
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.2,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.actionLabel,
    this.onAction,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                color: FanColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class FanSearchButton extends StatelessWidget {
  const FanSearchButton({required this.onTap, super.key, this.hint});

  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F2F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                size: 20,
                color: Color(0xFF98A2B3),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  hint ?? '搜索组合、艺人、专辑、小卡、用户',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uses the published admin image everywhere, retaining a placeholder on failure.
class FanImage extends StatelessWidget {
  const FanImage({
    required this.imageUrl,
    required this.fallback,
    super.key,
    this.fit = BoxFit.cover,
  });
  final String? imageUrl;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final source = ApiClient.resolveMediaUrl(imageUrl?.trim() ?? '');
    if (source.isEmpty) return fallback;
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (uri.path.contains('/catalog/images/')) {
        return PortraitImage(url: source, fallback: fallback, fit: fit);
      }
      return Image.network(
        source,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (_, child, frame, synchronous) =>
            synchronous || frame != null ? child : fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (source.startsWith('/')) {
      return Image.file(
        File(source),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}

class FanArtwork extends StatelessWidget {
  const FanArtwork({
    required this.startColor,
    required this.endColor,
    super.key,
    this.label,
    this.aspectRatio = 0.74,
    this.borderRadius = 18,
    this.showMark = true,
    this.imageUrl,
  });

  final Color startColor;
  final Color endColor;
  final String? label;
  final double aspectRatio;
  final double borderRadius;
  final bool showMark;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: FanImage(
          imageUrl: imageUrl,
          fallback: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [startColor, endColor],
                  ),
                ),
              ),
              CustomPaint(painter: _ArtworkPainter()),
              if (showMark)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.17),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Text(
                      label ?? 'F',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text(
                  'FAN OS  ·  ARCHIVE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.11);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .16),
      size.width * .38,
      soft,
    );
    canvas.drawCircle(
      Offset(size.width * .18, size.height * .68),
      size.width * .52,
      soft,
    );
    canvas.save();
    canvas.translate(size.width * .5, size.height * .46);
    canvas.rotate(-math.pi / 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * .76,
          height: size.height * .34,
        ),
        const Radius.circular(24),
      ),
      line,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class IdolAvatar extends StatelessWidget {
  const IdolAvatar({
    required this.idol,
    super.key,
    this.size = 58,
    this.selected = false,
  });

  final IdolProfile idol;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(selected ? 3 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected ? Border.all(color: FanColors.ink, width: 2) : null,
      ),
      child: ClipOval(
        child: FanImage(
          imageUrl: idol.thumbnailUrl ?? idol.imageUrl,
          fallback: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(idol.colorStart), Color(idol.colorEnd)],
              ),
            ),
            child: Text(
              idol.initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * .24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FavoriteIdolsShowcase extends StatelessWidget {
  const FavoriteIdolsShowcase({
    required this.idols,
    required this.primaryId,
    required this.onManage,
    required this.onOpen,
    super.key,
    this.title = '我的本命',
  });

  final List<IdolProfile> idols;
  final String? primaryId;
  final VoidCallback? onManage;
  final ValueChanged<IdolProfile> onOpen;
  final String title;

  @override
  Widget build(BuildContext context) {
    final primary = idols.where((idol) => idol.id == primaryId).firstOrNull;
    final ordered = [?primary, ...idols.where((idol) => idol.id != primaryId)];
    return Column(
      key: const Key('favorite-idols-showcase'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '✦  $title',
          actionLabel: onManage == null ? null : '管理',
          onAction: onManage,
        ),
        const SizedBox(height: 9),
        if (ordered.isEmpty)
          InkWell(
            key: const Key('favorite-idols-empty'),
            onTap: onManage,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FanColors.lavenderSoft.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.add_rounded, color: FanColors.lavender),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '添加你的本命',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 3),
                        Text('添加喜欢的艺人，发现更多相关内容。'),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          )
        else if (primary == null)
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ordered.length + (onManage == null ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) => index == ordered.length
                  ? _AddIdolButton(onTap: onManage!)
                  : _SecondaryIdol(
                      idol: ordered[index],
                      onTap: () => onOpen(ordered[index]),
                    ),
            ),
          )
        else
          SizedBox(
            height: 142,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _PrimaryIdolCard(
                    idol: ordered.first,
                    onTap: () => onOpen(ordered.first),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ordered.length > 1
                        ? ordered.length - 1
                        : (onManage == null ? 0 : 1),
                    separatorBuilder: (_, _) => const SizedBox(width: 11),
                    itemBuilder: (context, index) {
                      if (ordered.length == 1) {
                        return _AddIdolButton(onTap: onManage!);
                      }
                      final idol = ordered[index + 1];
                      return _SecondaryIdol(
                        idol: idol,
                        onTap: () => onOpen(idol),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PrimaryIdolCard extends StatelessWidget {
  const _PrimaryIdolCard({required this.idol, required this.onTap});

  final IdolProfile idol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('primary-idol-card'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 142,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(idol.colorStart), Color(idol.colorEnd)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FanImage(
              imageUrl: idol.thumbnailUrl ?? idol.imageUrl,
              fallback: const SizedBox.shrink(),
            ),
            if (idol.imageUrl?.isNotEmpty == true)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xB3141829)],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white.withValues(alpha: .72),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    idol.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    idol.secondaryName.isEmpty
                        ? idol.displayGroupName
                        : idol.secondaryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryIdol extends StatelessWidget {
  const _SecondaryIdol({required this.idol, required this.onTap});
  final IdolProfile idol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            IdolAvatar(idol: idol, size: 62),
            const SizedBox(height: 7),
            Text(
              idol.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            if (idol.secondaryName.isNotEmpty)
              Text(
                idol.secondaryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 9),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddIdolButton extends StatelessWidget {
  const _AddIdolButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: const SizedBox(
        width: 66,
        child: Column(
          children: [
            CircleAvatar(
              radius: 31,
              backgroundColor: FanColors.lavenderSoft,
              child: Icon(Icons.add_rounded, color: FanColors.ink),
            ),
            SizedBox(height: 7),
            Text('添加本命', style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class CollectibleCardTile extends StatelessWidget {
  const CollectibleCardTile({
    required this.card,
    super.key,
    this.onTap,
    this.compact = false,
    this.badge,
  });

  final CollectibleCard card;
  final VoidCallback? onTap;
  final bool compact;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              FanArtwork(
                imageUrl: card.imageUrl,
                startColor: Color(card.colorStart),
                endColor: Color(card.colorEnd),
                label: card.idolName.characters
                    .take(2)
                    .toString()
                    .toUpperCase(),
                borderRadius: 16,
              ),
              if (badge != null) Positioned(top: 8, right: 8, child: badge!),
            ],
          ),
          SizedBox(height: compact ? 7 : 9),
          FanEntityName(
            kind: 'idols',
            id: card.idolId,
            officialName: card.idolName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          if (card.tags.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAFE),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                card.tags.map((t) => t.name).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF7154B6)),
              ),
            )
          else
            Text(
              card.version,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class FanEmptyState extends StatelessWidget {
  const FanEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: FanColors.lavenderSoft,
                  ),
                  child: Icon(icon, color: FanColors.lavender, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 180,
                    child: OutlinedButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.label, super.key, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? FanColors.ink : Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: dark ? Colors.white : FanColors.ink,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

void showFanToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: FanColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
}
