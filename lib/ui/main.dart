// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:violetta_app/features/auth/auth_service.dart';
import 'package:violetta_app/features/auth/data/byok_vault_repository.dart';
import 'package:violetta_app/features/onboarding/presentation/violetta_app_root.dart';
import 'package:violetta_app/models/message_model.dart';

/// Тестовый 32-байтовый ключ для AES-256 шифрования коробки messages_box.
const List<int> _testEncryptionKey = <int>[
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
  0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(MessageModelAdapter());
  await Hive.openBox<MessageModel>(
    'messages_box',
    encryptionCipher: HiveAesCipher(_testEncryptionKey),
  );
  await ByokVaultRepository.instance.init();
  await AuthService.instance.init();

  if (kDebugMode) {
    await dotenv.load(fileName: '.env');
  }

  runApp(const ViolettaAppRoot());
}
