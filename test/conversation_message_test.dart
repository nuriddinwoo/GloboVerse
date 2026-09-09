import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/models/conversation_message.dart';

void main() {
  test('conversation messages round-trip through JSON', () {
    final timestamp = DateTime.utc(2026, 9, 9, 12, 30);
    final message = ConversationMessage(
      id: 'message-1',
      sender: ConversationMessageSender.me,
      text: 'Салом',
      translatedText: 'Hello',
      sourceLanguage: 'tg',
      targetLanguage: 'en',
      timestamp: timestamp,
      deliveryState: MessageDeliveryState.read,
    );

    final restored = ConversationMessage.fromJson(message.toJson());

    expect(restored.id, message.id);
    expect(restored.sender, ConversationMessageSender.me);
    expect(restored.text, 'Салом');
    expect(restored.translatedText, 'Hello');
    expect(restored.sourceLanguage, 'tg');
    expect(restored.targetLanguage, 'en');
    expect(restored.timestamp, timestamp);
    expect(restored.deliveryState, MessageDeliveryState.read);
    expect(restored.hasTranslation, isTrue);
  });

  test('unknown enum values use safe server defaults', () {
    final message = ConversationMessage.fromJson({
      'id': 'message-2',
      'text': 'Hello',
      'sender': 'unknown',
      'deliveryState': 'unknown',
      'translatedText': 42,
      'timestamp': false,
    });

    expect(message.sender, ConversationMessageSender.peer);
    expect(message.deliveryState, MessageDeliveryState.sent);
  });
}
