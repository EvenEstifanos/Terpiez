// redis_helper.dart
//
// Network layer for the game. Opens a short-lived connection to a Redis
// server (using the RedisJSON module) for each operation: logging in,
// reading Terpiez spawn locations, species info, and images, and backing
// up the player's catches.
//
// Expected Redis data layout:
//   locations  -> JSON array of { "lat", "lon", "id" } spawn points
//   terpiez    -> JSON object keyed by species id: { name, description,
//                 stats, image, thumbnail }
//   images     -> JSON object keyed by image id: base64-encoded PNG
//   <username> -> JSON object keyed by app id: the player's catch list

import 'package:redis/redis.dart';
import 'dart:convert';

/// Handles all communication with the Redis server.
///
/// Every network call is bounded by a 1-second timeout so a slow or
/// unreachable server never freezes the app.
class RedisHelper {
  // Server address is passed in at build time so it never lives in the code:
  //   flutter run --dart-define=REDIS_HOST=your.host --dart-define=REDIS_PORT=6380
  static const String _host =
      String.fromEnvironment('REDIS_HOST', defaultValue: 'localhost');
  static const int _port =
      int.fromEnvironment('REDIS_PORT', defaultValue: 6379);

  // Maximum time to wait on any single Redis operation.
  static const Duration _t = Duration(seconds: 1);

  /// Open a connection and authenticate.
  static Future<(RedisConnection, Command)> _open(
      String user, String pass) async {
    final conn = RedisConnection();
    final cmd = await conn.connect(_host, _port).timeout(_t);
    await cmd.send_object(['AUTH', user, pass]).timeout(_t);
    return (conn, cmd);
  }

  /// Verify that the given credentials work.
  static Future<bool> verifyLogin(String user, String pass) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      return true;
    } catch (_) {
      return false;
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }

  /// Lightweight connectivity check. Uses JSON.ARRLEN on `locations`
  /// so it works even on accounts restricted to JSON.* commands.
  static Future<void> ping(String user, String pass) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      final cmd = pair.$2;
      await cmd.send_object(['JSON.ARRLEN', 'locations', '.']).timeout(_t);
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }

  /// Read every element of the `locations` array, one at a time.
  static Future<List<Map<String, dynamic>>> readLocations(
      String user, String pass) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      final cmd = pair.$2;

      final rawLen = await cmd.send_object(['JSON.ARRLEN', 'locations', '.']).timeout(_t);
      final int count = int.parse(rawLen.toString());

      final List<Map<String, dynamic>> result = [];
      for (int i = 0; i < count; i++) {
        final raw = await cmd.send_object(['JSON.GET', 'locations', '.[$i]']).timeout(_t);
        if (raw != null) {
          final parsed = jsonDecode(raw.toString());
          if (parsed is Map) {
            result.add(Map<String, dynamic>.from(parsed));
          }
        }
      }
      return result;
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }

  /// Read species info for a single Terpiez ID.
  static Future<Map<String, dynamic>> readSpecies(
      String user, String pass, String speciesId) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      final cmd = pair.$2;
      final raw = await cmd.send_object(['JSON.GET', 'terpiez', '.$speciesId']).timeout(_t);
      return Map<String, dynamic>.from(jsonDecode(raw.toString()));
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }

  /// Read a single base64-encoded image by key.
  static Future<String> readImage(
      String user, String pass, String imageKey) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      final cmd = pair.$2;
      final raw = await cmd.send_object(['JSON.GET', 'images', '.$imageKey']).timeout(_t);
      return jsonDecode(raw.toString()) as String;
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }

  /// Write the user's game state to Redis under `username.appId`.
  static Future<void> saveState(String user, String pass, String appId,
      List<Map<String, dynamic>> catches) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      final cmd = pair.$2;

      final payload = jsonEncode(catches);
      try {
        await cmd.send_object(['JSON.SET', user, '.$appId', payload]).timeout(_t);
      } catch (_) {
        await cmd.send_object(['JSON.SET', user, '.', '{}']).timeout(_t);
        await cmd.send_object(['JSON.SET', user, '.$appId', payload]).timeout(_t);
      }
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }

  /// Make sure the root key and app-id sub-key exist.
  static Future<void> ensureKey(
      String user, String pass, String appId) async {
    RedisConnection? conn;
    try {
      final pair = await _open(user, pass);
      conn = pair.$1;
      final cmd = pair.$2;

      try {
        await cmd.send_object(['JSON.GET', user, '.$appId']).timeout(_t);
      } catch (_) {
        try {
          await cmd.send_object(['JSON.GET', user, '.']).timeout(_t);
        } catch (_) {
          await cmd.send_object(['JSON.SET', user, '.', '{}']).timeout(_t);
        }
        await cmd.send_object(['JSON.SET', user, '.$appId', '[]']).timeout(_t);
      }
    } finally {
      try { await conn?.close(); } catch (_) {}
    }
  }
}