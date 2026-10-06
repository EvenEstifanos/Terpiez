// list_screen.dart
//
// The player's collection: every caught species with its thumbnail.
// Tapping one opens its detail screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game_model.dart';
import 'detail_screen.dart';

class ListScreen extends StatelessWidget {
  const ListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameModel>(
      builder: (context, model, _) {
        final ids = model.caughtSpeciesIds;

        if (ids.isEmpty) {
          return const SafeArea(
            child: Center(
              child: Text('No Terpiez caught yet.',
                  style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        return SafeArea(
          child: ListView.builder(
            itemCount: ids.length,
            itemBuilder: (context, i) {
              final sid = ids[i];
              final info = model.speciesInfo(sid);
              final name = info?['name'] ?? 'Loading…';
              final thumbFile = model.thumbnail(sid);

              return ListTile(
                leading: SizedBox(
                  width: 48,
                  height: 48,
                  child: thumbFile != null
                      ? Image.file(thumbFile, fit: BoxFit.contain)
                      : const Icon(Icons.pest_control, size: 36),
                ),
                title: Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(speciesId: sid),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
