// stats_screen.dart
//
// Simple stats page: total Terpiez caught, days active, and player ID.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game_model.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameModel>(
      builder: (context, model, _) {
        return SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Statistics', style: TextStyle(fontSize: 30)),
                const SizedBox(height: 20),
                Text('Terpiez found: ${model.terpiezCaught}'),
                Text('Days Active: ${model.daysActive}'),
                const SizedBox(height: 30),
                Text(
                  'User: ${model.appId}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
