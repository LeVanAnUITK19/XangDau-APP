import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gia_xang_dau/app.dart';
import 'package:gia_xang_dau/core/push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pushNotifications.initialize();
  runApp(const ProviderScope(child: GiaXangDauApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    pushNotifications.handleInitialMessage();
  });
}
