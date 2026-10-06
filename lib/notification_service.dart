// notification_service.dart
//
// Local notification setup: a high-priority "Terpiez nearby" channel with a
// custom sound, and a silent channel for the background service. Tapping a
// proximity alert opens the app straight to the Finder tab.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Global tab index notifier: 0=stats, 1=finder, 2=list
final ValueNotifier<int> tabIndexNotifier = ValueNotifier<int>(0);

const String proximityChannelId = 'terpiez_proximity_v2';
const int proximityNotificationId = 1001;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse response) {}

void _onForegroundTap(NotificationResponse response) {
  if (response.payload == 'finder') {
    tabIndexNotifier.value = 1;
  }
}

Future<bool> initNotifications({bool requestPermission = true}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onForegroundTap,
    onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
  );

  // Proximity alert channel (uses custom sound)
  const proximityChannel = AndroidNotificationChannel(
    proximityChannelId,
    'Terpiez Proximity',
    description: 'Alerts when an uncaught Terpiez is within 20m',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('nearby'),
    playSound: true,
    enableVibration: true,
  );

  // Persistent background service channel (silent)
  const bgChannel = AndroidNotificationChannel(
    'terpiez_bg_service',
    'Terpiez Service',
    description: 'Persistent notification for the background location watcher',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  final android = notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(proximityChannel);
  await android?.createNotificationChannel(bgChannel);

  if (!requestPermission) return true;
  final granted = await android?.requestNotificationsPermission() ?? false;
  debugPrint('[notifications] permission granted: $granted');
  return granted;
}

Future<void> showProximityNotification(double distance) async {
  const androidDetails = AndroidNotificationDetails(
    proximityChannelId,
    'Terpiez Proximity',
    channelDescription: 'Alerts when an uncaught Terpiez is within 20m',
    importance: Importance.max,
    priority: Priority.max,
    sound: RawResourceAndroidNotificationSound('nearby'),
    playSound: true,
    enableVibration: true,
  );
  await notificationsPlugin.show(
    proximityNotificationId,
    'A Terpiez is near!',
    "It's ${distance.toStringAsFixed(1)}m away — go catch it!",
    const NotificationDetails(android: androidDetails),
    payload: 'finder',
  );
}

Future<int?> getInitialTabFromNotification() async {
  final details = await notificationsPlugin.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp == true &&
      details?.notificationResponse?.payload == 'finder') {
    return 1;
  }
  return null;
}
