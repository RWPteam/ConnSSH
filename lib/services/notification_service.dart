import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const int _connectionNotificationId = 1;
  static final NotificationService _instance = NotificationService._internal();

  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  bool _initialized = false;
  Future<void>? _initializing;

  NotificationService._internal() {
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  }

  factory NotificationService() {
    return _instance;
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      const AndroidInitializationSettings androidInitializationSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: androidInitializationSettings);

      await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

      if (Platform.isAndroid) {
        // 创建高优先级通知频道，用于前台服务
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'connection_channel',
          'ConnSSH 连接状态',
          description: '显示当前活跃的 SSH/SFTP 连接状态',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
          showBadge: false,
          enableLights: false,
        );

        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);

        print('通知频道创建成功');
      }

      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  Future<void> showConnectionNotification({
    required String connectionName,
    required String host,
    required int port,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'connection_channel',
            'ConnSSH 连接状态',
            channelDescription: '显示当前活跃的连接信息',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true, // 持久显示
            autoCancel: false, // 不允许用户滑动关闭
            onlyAlertOnce: true, // 只提醒一次
            showProgress: false,
            silent: true, // 静音显示
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        _connectionNotificationId,
        '连接中: $connectionName',
        '$host:$port',
        platformChannelSpecifics,
      );

      print('连接通知已显示: $connectionName');
    } catch (e) {
      print('显示通知失败: $e');
    }
  }

  Future<void> updateConnectionNotification({
    required String connectionName,
    required String host,
    required int port,
    required String status,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'connection_channel',
            'ConnSSH 连接状态',
            channelDescription: '显示当前活跃的连接信息',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true, // 持久显示
            autoCancel: false, // 不允许用户滑动关闭
            onlyAlertOnce: true, // 只提醒一次
            showProgress: false,
            silent: true, // 静音显示
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      await _flutterLocalNotificationsPlugin.show(
        _connectionNotificationId,
        '$status: $connectionName',
        '$host:$port',
        platformChannelSpecifics,
      );

      print('连接通知已更新: $status - $connectionName');
    } catch (e) {
      print('更新通知失败: $e');
    }
  }

  /// 取消连接通知
  Future<void> cancelConnectionNotification() async {
    if (!Platform.isAndroid) return;

    try {
      await _flutterLocalNotificationsPlugin.cancel(_connectionNotificationId);
    } catch (e) {
      print('取消通知失败: $e');
    }
  }
}
