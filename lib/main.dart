import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lbjconsole/screens/main_screen.dart';
import 'package:lbjconsole/util/train_type_util.dart';
import 'package:lbjconsole/util/loco_info_util.dart';
import 'package:lbjconsole/services/loco_type_service.dart';
import 'package:lbjconsole/services/background_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await _initializeNotifications();

  await BackgroundService.initialize();

  await Future.wait([
    TrainTypeUtil.initialize(),
    LocoInfoUtil.initialize(),
    LocoTypeService().initialize(),
  ]);

  runApp(const LBJReceiverApp());
}

Future<void> _initializeNotifications() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const LinuxInitializationSettings initializationSettingsLinux =
      LinuxInitializationSettings(defaultActionName: 'Open notification');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    linux: initializationSettingsLinux,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class LBJReceiverApp extends StatelessWidget {
  const LBJReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LBJ Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}
