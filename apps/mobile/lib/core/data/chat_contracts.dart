/// Phase 3 realtime chat wire contracts.
///
/// The current App does not connect to chat. Keeping this small contract in the
/// client makes future extraction to a dedicated realtime service compatible
/// with Fan OS entity IDs and versioned share targets.
enum ChatRoomType { group, direct }

enum ChatSubjectType { group, idol, custom }

enum ChatMessageType {
  text,
  image,
  sticker,
  idolCard('idol_card'),
  postShare('post_share'),
  collectionShare('collection_share'),
  system;

  const ChatMessageType([String? wireName]) : wireName = wireName ?? '';

  final String wireName;

  String get value => wireName.isEmpty ? name : wireName;
}

class ChatEntityReference {
  const ChatEntityReference({
    required this.type,
    required this.targetId,
    this.version = 1,
  });

  final String type;
  final String targetId;
  final int version;

  Map<String, dynamic> toJson() => {
    'type': type,
    'target_id': targetId,
    'version': version,
  };

  factory ChatEntityReference.fromJson(Map<String, dynamic> json) =>
      ChatEntityReference(
        type: json['type'] as String,
        targetId: json['target_id'] as String,
        version: (json['version'] as num?)?.toInt() ?? 1,
      );
}

class SendChatMessageCommand {
  const SendChatMessageCommand({
    required this.roomId,
    required this.clientMessageId,
    required this.messageType,
    this.content,
    this.target,
    this.replyMessageId,
  });

  final String roomId;
  final String clientMessageId;
  final ChatMessageType messageType;
  final String? content;
  final ChatEntityReference? target;
  final String? replyMessageId;

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'client_message_id': clientMessageId,
    'message_type': messageType.value,
    if (content != null) 'content': content,
    if (target != null) 'target': target!.toJson(),
    if (replyMessageId != null) 'reply_message_id': replyMessageId,
  };
}

class ChatReadCommand {
  const ChatReadCommand({required this.roomId, required this.lastReadSequence});

  final String roomId;
  final int lastReadSequence;

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'last_read_sequence': lastReadSequence,
  };
}
