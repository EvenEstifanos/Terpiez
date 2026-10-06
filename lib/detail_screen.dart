// detail_screen.dart
//
// Detail view for a caught species: image, name, stats, description, and a
// map of every spot it was caught, with a falling-particle background
// animation built on Flutter's physics simulations.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'game_model.dart';

// ── Falling particle: one animated shape driven by gravity + friction ──
class _Particle extends StatefulWidget {
  final double width, height, startX, time, drag, velocity;
  const _Particle({
    required this.width,
    required this.height,
    required this.startX,
    required this.time,
    required this.drag,
    required this.velocity,
  });
  @override
  State<_Particle> createState() => _ParticleState();
}

class _ParticleState extends State<_Particle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Simulation _yS, _xS;
  late double _a;

  @override
  void initState() {
    super.initState();
    _a = 2 * widget.height / (widget.time * widget.time);
    _yS = GravitySimulation(_a, 0, widget.height, 0);
    _xS = FrictionSimulation(widget.drag, widget.startX, widget.velocity);
    _ctrl = AnimationController(vsync: this, upperBound: widget.time);
    _go();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _xS = FrictionSimulation(widget.drag, widget.startX, widget.velocity);
        _yS = GravitySimulation(_a, 0, widget.height, 0);
        _ctrl.value = 0;
        _go();
      }
    });
  }

  void _go() => _ctrl.animateTo(widget.time,
      duration: Duration(milliseconds: (widget.time * 1000).round()));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Stack(children: [
          Positioned(
            left: _xS.x(t).clamp(0.0, widget.width - 12),
            top: _yS.x(t).clamp(0.0, widget.height - 12),
            child: Container(
              width: 12,
              height: 12,
              decoration: const ShapeDecoration(
                shape: CircleBorder(side: BorderSide.none),
                color: Color(0x55800000),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ── Detail screen ────────────────────────────────────────────────────
class DetailScreen extends StatelessWidget {
  final String speciesId;
  const DetailScreen({super.key, required this.speciesId});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameModel>(
      builder: (context, model, _) {
        final info = model.speciesInfo(speciesId);
        final name = info?['name'] ?? 'Unknown';
        final desc = info?['description'] ?? '';
        final stats = (info?['stats'] as Map<String, dynamic>?) ?? {};
        final imgFile = model.fullImage(speciesId);
        final catches = model.catchesFor(speciesId);

        return Scaffold(
          appBar: AppBar(
            title: Text(name, style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF800000),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: LayoutBuilder(
            builder: (context, box) {
              final rng = Random();
              final particles = List.generate(8, (_) => _Particle(
                width: box.maxWidth,
                height: box.maxHeight,
                startX: rng.nextDouble() * box.maxWidth,
                time: 4 + rng.nextDouble() * 3,
                drag: 0.3 + rng.nextDouble() * 0.3,
                velocity: 20 * (rng.nextDouble() - 0.5),
              ));

              return Stack(
                children: [
                  // Particles behind content
                  ...particles,

                  // Scrollable content
                  OrientationBuilder(
                    builder: (context, orientation) {
                      if (orientation == Orientation.landscape) {
                        // ── Landscape: 3 columns side by side ──
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left: image + name
                              Expanded(
                                flex: 2,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (imgFile != null)
                                      Image.file(imgFile,
                                          height: 160, fit: BoxFit.contain)
                                    else
                                      const Icon(Icons.pest_control, size: 100),
                                    const SizedBox(height: 8),
                                    Text(name,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Middle: map + stats
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _catchMap(catches),
                                    const SizedBox(height: 8),
                                    _statsColumn(stats),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Right: description
                              Expanded(
                                flex: 3,
                                child: SingleChildScrollView(
                                  child: Text(desc,
                                      style: const TextStyle(fontSize: 14)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // ── Portrait: single scrolling column ──
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (imgFile != null)
                                Image.file(imgFile,
                                    height: 220, fit: BoxFit.contain)
                              else
                                const Icon(Icons.pest_control, size: 120),
                              const SizedBox(height: 12),
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _catchMap(catches)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _statsColumn(stats)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(desc,
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _catchMap(List<Map<String, dynamic>> catches) {
    if (catches.isEmpty) return const SizedBox(height: 140);

    final pins = <Marker>[];
    for (final c in catches) {
      final lat = (c['lat'] as num).toDouble();
      final lon = (c['lon'] as num).toDouble();
      pins.add(Marker(
        point: LatLng(lat, lon),
        width: 32,
        height: 32,
        child: const Icon(Icons.location_on, color: Color(0xFF800000), size: 32),
      ));
    }

    // Fit map to show all pins
    double minLat = pins.map((m) => m.point.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = pins.map((m) => m.point.latitude).reduce((a, b) => a > b ? a : b);
    double minLon = pins.map((m) => m.point.longitude).reduce((a, b) => a < b ? a : b);
    double maxLon = pins.map((m) => m.point.longitude).reduce((a, b) => a > b ? a : b);

    // If single pin or all same location, use fixed zoom
    final bool singleLocation = (maxLat - minLat < 0.00001 && maxLon - minLon < 0.00001);

    const pad = 0.0008;
    final bounds = LatLngBounds(
      LatLng(minLat - pad, minLon - pad),
      LatLng(maxLat + pad, maxLon + pad),
    );

    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);

    return SizedBox(
      height: 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: singleLocation
                ? null
                : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(20)),
            initialCenter: center,
            initialZoom: singleLocation ? 17 : 16,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.terpiez',
            ),
            MarkerLayer(markers: pins),
          ],
        ),
      ),
    );
  }

    Widget _statsColumn(Map<String, dynamic> stats) {
    if (stats.isEmpty) return const Text('No stats');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: stats.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.key),
              Text(e.value.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }
}