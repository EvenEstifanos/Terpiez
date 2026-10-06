// sound_service.dart
//
// Plays the catch sound effect from the bundled assets.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

final AudioPlayer _catchPlayer = AudioPlayer();

Future<void> playCatchSound() async {
  try {
    await _catchPlayer.stop();
    await _catchPlayer.play(AssetSource('sounds/catch.wav'));
  } catch (e) {
    debugPrint('[sound] playCatchSound error: $e');
  }
}
