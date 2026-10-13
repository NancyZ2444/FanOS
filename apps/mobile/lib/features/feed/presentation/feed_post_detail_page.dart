import 'package:fan_os/app/theme.dart';
import 'package:fan_os/core/data/social_feed_models.dart';
import 'package:fan_os/core/state/app_state.dart';
import 'package:fan_os/core/widgets/fan_widgets.dart';
import 'package:fan_os/features/feed/presentation/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedPostDetailPage extends ConsumerStatefulWidget {
  const FeedPostDetailPage({required this.postId, this.initialPost, super.key});

  final String postId;
  final SocialFeedPost? initialPost;

  @override
  ConsumerState<FeedPostDetailPage> createState() => _FeedPostDetailPageState();
}

class _FeedPostDetailPageState extends ConsumerState<FeedPostDetailPage> {
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  FeedComment? _replyingTo;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (widget.initialPost != null) {
        ref.read(feedEngagementProvider.notifier).registerPosts([
          widget.initialPost!,
        ]);
      }
      ref
          .read(feedEngagementProvider.notifier)
          .ensureDemoComments(widget.postId);
      ref.read(socialFeedProvider.notifier).markViewed(widget.postId);
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _openOriginal(SocialFeedPost post) async {
    try {
      final deepLink = Uri.tryParse(post.deepLinkUrl ?? '');
      if (deepLink != null && await canLaunchUrl(deepLink)) {
        await launchUrl(deepLink, mode: LaunchMode.externalApplication);
        return;
      }
      if (await launchUrl(
        Uri.parse(post.originalUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Show a readable fallback below.
    }
    if (mounted) showFanToast(context, '暂时无法打开${post.platform.displayName}');
  }

  void _startReply(FeedComment comment) {
    setState(() => _replyingTo = comment);
    _commentFocus.requestFocus();
  }

  void _sendComment() {
    if (ref.read(sessionProvider).isGuest) {
      showFanToast(context, '登录后即可发表评论');
      context.push('/login');
      return;
    }
    if (_commentController.text.trim().isEmpty) return;
    ref
        .read(feedEngagementProvider.notifier)
        .addComment(
          widget.postId,
          _commentController.text,
          replyingTo: _replyingTo,
        );
    _commentController.clear();
    _commentFocus.unfocus();
    setState(() => _replyingTo = null);
    showFanToast(context, '评论已发布');
  }

  @override
  Widget build(BuildContext context) {
    final engagement = ref.watch(feedEngagementProvider);
    final post = widget.initialPost ?? engagement.postsById[widget.postId];
    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('动态详情')),
        body: const FanEmptyState(
          icon: Icons.link_off_rounded,
          title: '动态不可访问',
          message: '该动态可能已删除或尚未同步。',
        ),
      );
    }
    final comments =
        engagement.commentsByPost[post.id] ?? const <FeedComment>[];
    return Scaffold(
      appBar: AppBar(title: const Text('动态详情')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                SocialFeedCard(
                  post: post,
                  expanded: true,
                  viewed: true,
                  onToggleExpanded: () {},
                  onOpenOriginal: () => _openOriginal(post),
                  onOpenAuthor: () => context.push(post.authorRoute),
                  onOpenGroup: () => context.push(post.groupRoute),
                  onOpenComments: () => _commentFocus.requestFocus(),
                  onOpenRelation: post.relation == null
                      ? null
                      : () => context.push(post.relation!.route),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      '评论 ${engagement.commentCount(post)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    const Text(
                      'Fan OS 站内互动',
                      style: TextStyle(
                        color: FanColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: Text('还没有评论，来分享第一条想法吧')),
                  )
                else
                  for (final comment in comments)
                    _CommentTile(
                      comment: comment,
                      liked: engagement.likedCommentIds.contains(comment.id),
                      likeCount: engagement.commentLikeCount(comment),
                      reported: engagement.reportedCommentIds.contains(
                        comment.id,
                      ),
                      onReply: () => _startReply(comment),
                      onLike: () => ref
                          .read(feedEngagementProvider.notifier)
                          .toggleCommentLike(comment.id),
                      onDelete: () {
                        ref
                            .read(feedEngagementProvider.notifier)
                            .deleteComment(comment);
                        showFanToast(context, '评论已删除');
                      },
                      onReport: () {
                        ref
                            .read(feedEngagementProvider.notifier)
                            .reportComment(comment.id);
                        showFanToast(context, '已收到举报，我们会尽快审核');
                      },
                    ),
              ],
            ),
          ),
          _CommentComposer(
            controller: _commentController,
            focusNode: _commentFocus,
            replyingTo: _replyingTo,
            onCancelReply: () => setState(() => _replyingTo = null),
            onSend: _sendComment,
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.liked,
    required this.likeCount,
    required this.reported,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.onReport,
  });

  final FeedComment comment;
  final bool liked;
  final int likeCount;
  final bool reported;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: comment.parentId == null ? 0 : 34),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: comment.isMine
              ? FanColors.lavenderSoft
              : FanColors.blueSoft,
          child: Text(comment.userName.characters.first),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                comment.userName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onSelected: (value) =>
                  value == 'delete' ? onDelete() : onReport(),
              itemBuilder: (_) => [
                if (comment.isMine)
                  const PopupMenuItem(value: 'delete', child: Text('删除评论'))
                else
                  PopupMenuItem(
                    value: 'report',
                    enabled: !reported,
                    child: Text(reported ? '已举报' : '举报评论'),
                  ),
              ],
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comment.replyToName != null)
              Text(
                '回复 @${comment.replyToName}',
                style: const TextStyle(color: FanColors.lavender, fontSize: 12),
              ),
            Text(
              comment.content,
              style: const TextStyle(color: FanColors.ink, height: 1.4),
            ),
            Row(
              children: [
                Text(
                  _commentTime(comment.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(onPressed: onReply, child: const Text('回复')),
                const Spacer(),
                TextButton.icon(
                  onPressed: onLike,
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 15,
                    color: liked ? FanColors.coral : FanColors.textSecondary,
                  ),
                  label: Text('$likeCount'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FeedComment? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyingTo != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '回复 ${replyingTo!.userName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: FanColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onCancelReply,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('feed-comment-input'),
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: replyingTo == null ? '说点什么…' : '写下回复…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('send-feed-comment'),
                  onPressed: onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _commentTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes}分钟前';
  if (difference.inDays < 1) return '${difference.inHours}小时前';
  return '${time.month}月${time.day}日';
}
