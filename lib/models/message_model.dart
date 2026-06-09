import 'package:hive/hive.dart';

part 'message_model.g.dart';

@HiveType(typeId: 0)
class MessageModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String senderId;

  @HiveField(2)
  String originalText;

  @HiveField(3)
  String sourceLanguageCode;

  @HiveField(4)
  Map<String, String> translations;

  @HiveField(5)
  DateTime timestamp;

  @HiveField(6)
  bool isAudio;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.originalText,
    required this.sourceLanguageCode,
    required this.translations,
    required this.timestamp,
    required this.isAudio,
  });

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? originalText,
    String? sourceLanguageCode,
    Map<String, String>? translations,
    DateTime? timestamp,
    bool? isAudio,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      originalText: originalText ?? this.originalText,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      translations: translations ?? Map<String, String>.from(this.translations),
      timestamp: timestamp ?? this.timestamp,
      isAudio: isAudio ?? this.isAudio,
    );
  }
}
