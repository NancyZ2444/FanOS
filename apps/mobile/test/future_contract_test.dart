import 'package:fan_os/core/data/chat_contracts.dart';
import 'package:fan_os/core/data/community_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('community drafts use a separate version-ready payload', () {
    final draft = CommunityPostDraft(
      content: '今天的收藏',
      subjectType: CommunitySubjectType.idol,
      subjectId: 'idol-aria',
      media: const [
        CommunityMediaDraft(
          type: CommunityMediaType.image,
          url: 'https://cdn.example/community/post.jpg',
        ),
      ],
    );

    expect(draft.toJson(), {
      'content': '今天的收藏',
      'subject_type': 'idol',
      'subject_id': 'idol-aria',
      'media': [
        {
          'media_type': 'image',
          'url': 'https://cdn.example/community/post.jpg',
        },
      ],
    });
  });

  test('chat share commands preserve stable Fan OS entity references', () {
    const command = SendChatMessageCommand(
      roomId: 'room-1',
      clientMessageId: 'ios-1001',
      messageType: ChatMessageType.idolCard,
      target: ChatEntityReference(type: 'card', targetId: 'card-aria-01'),
    );

    expect(command.toJson(), {
      'room_id': 'room-1',
      'client_message_id': 'ios-1001',
      'message_type': 'idol_card',
      'target': {'type': 'card', 'target_id': 'card-aria-01', 'version': 1},
    });
  });
}
