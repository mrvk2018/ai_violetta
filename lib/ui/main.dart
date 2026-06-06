// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:violetta_app/features/onboarding/presentation/violetta_app_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  if (!kIsWeb) {
    await NaverMapSdk.instance.initialize(
      clientId: dotenv.env['NAVER_MAP_CLIENT_ID'] ?? 'YOUR_NAVER_CLIENT_ID_IF_NEEDED',
      onAuthFailed: (ex) => debugPrint('Naver Map Auth Failed: $ex'),
    );
  }
  runApp(const ViolettaAppRoot());
}
