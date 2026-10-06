// background_service.dart
//
// Runs while the app is closed (Android foreground service). Every 20
// seconds it checks the player's GPS position against the uncaught Terpiez
// list and sends a notification when one is within 20 m (at most once
// every 30 seconds).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

const String _bgLocationsKey = 'bg_uncaught_locations';
const String _bgLastNotifKey = 'bg_last_notif_ms';

/// Called from GameModel whenever uncaught locations change so the
/// background service always has an up-to-date list to check against.
Future<void> saveBgLocations(List<Map<String, dynamic>> locations) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_bgLocationsKey, jsonEncode(locations));
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'terpiez_bg_service',
      initialNotificationTitle: 'Terpiez',
      initialNotificationContent: 'Watching for nearby Terpiez…',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

Future<void> startBackgroundService() async {
  final service = FlutterBackgroundService();
  if (!await service.isRunning()) {
    await service.startService();
  }
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  // Initialize Flutter plugins in the background isolate.
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Terpiez',
      content: 'Watching for nearby Terpiez…',
    );
  }

  // Set up the notification plugin for use in this isolate.
  await initNotifications(requestPermission: false);

  // Poll for nearby Terpiez every 20 seconds.
  Timer.periodic(const Duration(seconds: 20), (_) async {
    await _checkProximity();
  });
}

Future<void> _checkProximity() async {
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 10));

    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_bgLocationsKey);
    if (json == null || json.isEmpty) return;

    final locations = (jsonDecode(json) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (locations.isEmpty) return;

    const calc = Distance();
    final myLoc = LatLng(pos.latitude, pos.longitude);

    double? best;
    for (final loc in locations) {
      final d = calc.as(
        LengthUnit.Meter,
        myLoc,
        LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lon'] as num).toDouble(),
        ),
      );
      if (best == null || d < best) best = d;
    }

    if (best == null || best > 20.0) return;

    // Throttle: fire at most once every 30 seconds.
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastMs = prefs.getInt(_bgLastNotifKey) ?? 0;
    if (now - lastMs < 30000) return;

    await prefs.setInt(_bgLastNotifKey, now);
    await showProximityNotification(best);
    debugPrint('[bg] proximity notification fired (${best.toStringAsFixed(1)}m)');
  } catch (e) {
    debugPrint('[bg] _checkProximity error: $e');
  }
}
