enum ConversationMessageSender { me, peer, system }

enum MessageDeliveryState { sending, sent, failed }

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.translatedText,
    this.sourceLanguage = 'auto',
    this.targetLanguage = 'en',
    this.deliveryState = MessageDeliveryState.sent,
  });

  final String id;
  final ConversationMessageSender sender;
  final String text;
  final String? translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final DateTime timestamp;
  final MessageDeliveryState deliveryState;

  bool get isMine => sender == ConversationMessageSender.me;
  bool get hasTranslation =>
      translatedText != null &&
      translatedText!.trim().isNotEmpty &&
      translatedText!.trim() != text.trim();

  ConversationMessage copyWith({
    String? id,
    ConversationMessageSender? sender,
    String? text,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    DateTime? timestamp,
    MessageDeliveryState? deliveryState,
  }) {
    return ConversationMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      translatedText: translatedText ?? this.translatedText,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      timestamp: timestamp ?? this.timestamp,
      deliveryState: deliveryState ?? this.deliveryState,
    );
  }

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    final timestampValue = json['timestamp'];
    final timestamp = timestampValue is String
        ? DateTime.tryParse(timestampValue)
        : null;
    return ConversationMessage(
      id: _stringValue(json['id']),
      sender: _senderFromJson(_nullableStringValue(json['sender'])),
      text: _stringValue(json['text']),
      translatedText: _nullableStringValue(json['translatedText']),
      sourceLanguage: _stringValue(json['sourceLanguage'], fallback: 'auto'),
      targetLanguage: _stringValue(json['targetLanguage'], fallback: 'en'),
      timestamp: timestamp ?? DateTime.now(),
      deliveryState: _deliveryFromJson(
        _nullableStringValue(json['deliveryState']),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender.name,
      'text': text,
      if (translatedText != null) 'translatedText': translatedText,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'deliveryState': deliveryState.name,
    };
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    return value is String ? value : fallback;
  }

  static String? _nullableStringValue(Object? value) {
    return value is String ? value : null;
  }

  static ConversationMessageSender _senderFromJson(String? value) {
    return ConversationMessageSender.values.firstWhere(
      (sender) => sender.name == value,
      orElse: () => ConversationMessageSender.peer,
    );
  }

  static MessageDeliveryState _deliveryFromJson(String? value) {
    return MessageDeliveryState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => MessageDeliveryState.sent,
    );
  }
}
