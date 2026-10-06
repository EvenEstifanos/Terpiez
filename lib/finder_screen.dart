// finder_screen.dart
//
// The main gameplay screen: a live map showing the player and the nearest
// uncaught Terpiez, the distance to it, and shake-to-catch. Plays a catch
// sound and shows the caught creature in a dialog.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'game_model.dart';
import 'settings_model.dart';
import 'sound_service.dart';

class FinderScreen extends StatefulWidget {
  const FinderScreen({super.key});

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  final MapController _mapController = MapController();
  bool _catching = false;

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  bool _shakeLocked = false;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    // Shake detection: a strong enough accelerometer spike triggers a catch
    // attempt; the 800 ms lock stops one shake from counting twice.
    _accelSub = userAccelerometerEventStream().listen((e) {
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (mag >= 10 && !_shakeLocked) {
        _shakeLocked = true;
        _onShake();
        Future.delayed(const Duration(milliseconds: 800), () {
          _shakeLocked = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    super.dispose();
  }

  /// Asks for location permission, then streams GPS updates into the
  /// game model and keeps the map centered on the player.
  Future<void> _startLocationUpdates() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 1),
    ).listen((Position pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        Provider.of<GameModel>(context, listen: false).updateLocation(loc);
        try {
          _mapController.move(loc, _mapController.camera.zoom);
        } catch (_) {}
      }
    });
  }

  Future<void> _onShake() async {
    if (!mounted) return;
    final model = Provider.of<GameModel>(context, listen: false);
    // Only catch when online, in range, and not already mid-catch.
    if (!model.canCatch || !model.connected || _catching) return;
    await _doCatch(model);
  }

  Future<void> _doCatch(GameModel model) async {
    if (_catching) return;
    setState(() => _catching = true);

    // Play the catch sound immediately so the user knows the shake registered,
    // before the download/display is complete.
    final soundEnabled =
        Provider.of<SettingsModel>(context, listen: false).soundEnabled;
    if (soundEnabled) playCatchSound();

    final sid = await model.catchTerpiez();
    if (!mounted) return;
    setState(() => _catching = false);
    if (sid != null) {
      _showCatchDialog(sid, model);
    }
  }

  void _showCatchDialog(String sid, GameModel model) {
    final info = model.speciesInfo(sid);
    final File? img = model.fullImage(sid);
    final String name = (info?['name'] ?? 'Terpiez') as String;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        // Cap image height so the dialog fits in landscape too.
        final screenH = MediaQuery.of(ctx).size.height;
        final imageMax = screenH * 0.45;

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: imageMax),
                      child: img != null
                          ? Image.file(img, fit: BoxFit.contain)
                          : const Icon(Icons.pest_control,
                              size: 120, color: Color(0xFF800000)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('You caught a Terpiez!',
                      style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Great!',
                          style: TextStyle(
                              color: Color(0xFF800000), fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Consumer<GameModel>(
      builder: (context, model, _) {
        final markers = <Marker>[];
        if (model.currentLocation != null) {
          if (model.canCatch) {
            // Pulsing halo shows the player they're close enough to catch.
            markers.add(Marker(
              point: model.currentLocation!,
              width: 80,
              height: 80,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.lightBlue.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.priority_high,
                      color: Colors.lightBlue, size: 32),
                ),
              ),
            ));
          }
          markers.add(Marker(
            point: model.currentLocation!,
            width: 20,
            height: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ));
        }
        final closest = model.closestPoint;
        if (closest != null) {
          markers.add(Marker(
            point: closest,
            width: 30,
            height: 30,
            child: const Icon(Icons.pest_control,
                color: Color(0xFF800000), size: 30),
          ));
        }

        // OpenStreetMap tiles + markers for the player and nearest Terpiez.
        final map = model.loadingLocations
            ? const Center(child: CircularProgressIndicator())
            : FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: model.currentLocation ??
                      const LatLng(38.9897, -76.9378),
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.terpiez',
                  ),
                  MarkerLayer(markers: markers),
                ],
              );

        final info = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Closest Terpiez:', style: TextStyle(fontSize: 18)),
            Text(
              model.closestDistance != null
                  ? '${model.closestDistance!.toStringAsFixed(1)}m'
                  : model.remaining.isEmpty
                      ? 'All caught!'
                      : '<undefined>m',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            if (_catching)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (model.canCatch)
              const Text('Shake to catch!',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF800000)))
            else
              const Text('Get closer to catch',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        );

        return SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child:
                    Text('Terpiez Finder', style: TextStyle(fontSize: 30)),
              ),
              // Side-by-side layout in landscape, stacked in portrait.
              if (landscape)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: map),
                      const SizedBox(width: 20),
                      info,
                      const SizedBox(width: 20),
                    ],
                  ),
                )
              else ...[
                SizedBox(height: 400, child: map),
                const SizedBox(height: 16),
                info,
              ],
            ],
          ),
        );
      },
    );
  }
}