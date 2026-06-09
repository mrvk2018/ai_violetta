import 'package:hive/hive.dart';
import 'package:violetta_app/models/message_model.dart';

class ChatRepository {
  final Box<MessageModel> _box;

  ChatRepository(this._box);

  Future<void> saveMessage(MessageModel message) async {
    await _box.put(message.id, message);
  }

  List<MessageModel> getAllMessages() {
    final List<MessageModel> messages = _box.values.toList();
    messages.sort((MessageModel a, MessageModel b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  Future<void> addTranslation(
    String messageId,
    String langCode,
    String translatedText,
  ) async {
    final MessageModel? message = _box.get(messageId);
    if (message == null) {
      throw StateError('Message with id "$messageId" not found.');
    }

    final Map<String, String> updatedTranslations = Map<String, String>.from(message.translations);
    updatedTranslations[langCode] = translatedText;

    final MessageModel updatedMessage = message.copyWith(translations: updatedTranslations);
    await _box.put(messageId, updatedMessage);
  }

  Future<void> deleteMessage(String messageId) async {
    await _box.delete(messageId);
  }
}
