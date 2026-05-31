import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'data/database_helper.dart';
import 'services/background_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for Windows/Desktop SQLite support
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Initialize SQLite and Bootstrap JSON data
  await DatabaseHelper.instance.database;
  await DatabaseHelper.instance.bootstrapData();

  // Initialize Background Service only on mobile (not supported on Windows/Desktop)
  if (Platform.isAndroid || Platform.isIOS) {
    // ── Create notification channel BEFORE starting the background service ──
    // Android 8+ requires the channel to exist with importance >= LOW
    // before startForeground() can post to it.
    if (Platform.isAndroid) {
      final flnPlugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await flnPlugin.initialize(const InitializationSettings(android: androidInit));

      const channel = AndroidNotificationChannel(
        'metro_tracking_channel',          // must match notificationChannelId
        'Metro Tracking',
        description: 'Live journey tracking for Metro Wake-Up',
        importance: Importance.low,
        enableVibration: false,
        playSound: false,
      );
      await flnPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await initializeService();
  }

  runApp(const MetroWakeApp());
}

class MetroWakeApp extends StatelessWidget {
  const MetroWakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Metro Wake-Up',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.blueAccent,
          surface: Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
