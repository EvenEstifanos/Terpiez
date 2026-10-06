// game_model.dart
//
// The central game state (ChangeNotifier, shared via Provider). Owns:
//   - the player's ID, login, and connection status
//   - Terpiez spawn locations and which ones have been caught
//   - distance math for "closest Terpiez" and the 10 m catch radius
//   - saving everything locally (works offline) and backing it up to Redis

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_service.dart' show saveBgLocations;
import 'redis_helper.dart';

// Generates a random UUID v4 used as this install's unique player ID
// (written by hand to avoid pulling in an extra package).
String _makeUuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${b.sublist(0, 4).map(h).join()}-'
      '${b.sublist(4, 6).map(h).join()}-'
      '${b.sublist(6, 8).map(h).join()}-'
      '${b.sublist(8, 10).map(h).join()}-'
      '${b.sublist(10).map(h).join()}';
}

class GameModel extends ChangeNotifier {
  // ── Persistent identity ──────────────────────────────────────────
  SharedPreferences? _prefs;
  String _appId = '';
  DateTime? _firstRun;

  // ── Login (credentials kept in encrypted secure storage) ────────
  final _vault = const FlutterSecureStorage();
  String? _rUser;
  String? _rPass;
  bool _loggedIn = false;
  bool _ready = false;

  // ── Map / game state ─────────────────────────────────────────────
  LatLng? currentLocation;
  List<Map<String, dynamic>> _serverLocations = [];
  bool _loadingLocations = false;

  List<Map<String, dynamic>> _catches = [];
  Map<String, Map<String, dynamic>> _species = {};
  String? _filesDir;

  // ── Connection state: updated by a periodic background probe ────
  bool connected = true;
  Timer? _probeTimer;

  bool get loggedIn => _loggedIn;
  bool get ready => _ready;
  bool get loadingLocations => _loadingLocations;
  String get appId => _appId;
  int get terpiezCaught => _catches.length;

  int get daysActive {
    if (_firstRun == null) return 0;
    return DateTime.now().difference(_firstRun!).inDays;
  }

  List<Map<String, dynamic>> get serverLocations => _serverLocations;

  /// Spawn points the player hasn't caught yet.
  List<Map<String, dynamic>> get remaining {
    return _serverLocations.where((s) {
      return !_catches.any(
          (c) => c['lat'] == s['lat'] && c['lon'] == s['lon']);
    }).toList();
  }

  List<String> get caughtSpeciesIds =>
      _catches.map((c) => c['id'] as String).toSet().toList();

  Map<String, dynamic>? speciesInfo(String id) => _species[id];

  List<Map<String, dynamic>> catchesFor(String speciesId) =>
      _catches.where((c) => c['id'] == speciesId).toList();

  File? thumbnail(String speciesId) => _imageFile(speciesId, thumb: true);
  File? fullImage(String speciesId) => _imageFile(speciesId, thumb: false);

  File? _imageFile(String speciesId, {required bool thumb}) {
    final info = _species[speciesId];
    if (info == null || _filesDir == null) return null;
    final key = thumb ? 'thumbFile' : 'imageFile';
    final path = '$_filesDir/${info[key]}';
    final f = File(path);
    return f.existsSync() ? f : null;
  }

  /// Distance in meters to the nearest uncaught Terpiez.
  double? get closestDistance {
    if (currentLocation == null) return null;
    const calc = Distance();
    double? best;
    for (final loc in remaining) {
      final d = calc.as(LengthUnit.Meter, currentLocation!,
          LatLng((loc['lat'] as num).toDouble(),
                  (loc['lon'] as num).toDouble()));
      if (best == null || d < best) best = d;
    }
    return best;
  }

  /// A Terpiez can be caught once the player is within 10 meters.
  bool get canCatch {
    final d = closestDistance;
    return d != null && d <= 10.0;
  }

  Map<String, dynamic>? get _closestEntry {
    if (currentLocation == null) return null;
    const calc = Distance();
    double best = double.infinity;
    Map<String, dynamic>? winner;
    for (final loc in remaining) {
      final d = calc.as(LengthUnit.Meter, currentLocation!,
          LatLng((loc['lat'] as num).toDouble(),
                  (loc['lon'] as num).toDouble()));
      if (d < best) { best = d; winner = loc; }
    }
    return winner;
  }

  LatLng? get closestPoint {
    final e = _closestEntry;
    if (e == null) return null;
    return LatLng(
        (e['lat'] as num).toDouble(), (e['lon'] as num).toDouble());
  }

  /// Startup: loads the player ID, first-run date, saved login, and any
  /// cached game state from disk so the app works before the network does.
  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();

    _appId = _prefs!.getString('appId') ?? '';
    if (_appId.isEmpty) {
      _appId = _makeUuid();
      await _prefs!.setString('appId', _appId);
    }

    final stored = _prefs!.getString('firstRun');
    if (stored != null) {
      _firstRun = DateTime.parse(stored);
    } else {
      _firstRun = DateTime.now();
      await _prefs!.setString('firstRun', _firstRun!.toIso8601String());
    }

    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/downloads');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _filesDir = dir.path;
      }
    } catch (_) {
      final doc = await getApplicationDocumentsDirectory();
      final dir = Directory('${doc.path}/downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _filesDir = dir.path;
    }

    _rUser = await _vault.read(key: 'ru');
    _rPass = await _vault.read(key: 'rp');
    _loggedIn = _rUser != null && _rPass != null;

    await _loadLocal();

    _ready = true;
    notifyListeners();

    if (_loggedIn) _startProbe();
  }

  // Ping the server every 10 seconds (plus once immediately) and flip
  // `connected` when it changes, so the UI can warn the player.
  void _startProbe() {
    _probeTimer?.cancel();
    _runProbe();
    _probeTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _runProbe());
  }

  Future<void> _runProbe() async {
    if (_rUser == null || _rPass == null) return;
    debugPrint('[probe] pinging...');
    bool ok;
    try {
      await RedisHelper.ping(_rUser!, _rPass!);
      ok = true;
    } catch (e) {
      debugPrint('[probe] ping failed: $e');
      ok = false;
    }
    debugPrint('[probe] was=$connected now=$ok');
    if (ok != connected) {
      connected = ok;
      notifyListeners();
    }
  }

  /// Verifies credentials against Redis, stores them securely on success,
  /// then downloads spawn locations and starts the connection probe.
  Future<bool> tryLogin(String user, String pass) async {
    final ok = await RedisHelper.verifyLogin(user, pass);
    if (!ok) return false;

    await _vault.write(key: 'ru', value: user);
    await _vault.write(key: 'rp', value: pass);
    _rUser = user;
    _rPass = pass;
    _loggedIn = true;
    connected = true;
    notifyListeners();

    try { await RedisHelper.ensureKey(user, pass, _appId); } catch (_) {}
    await pullLocations();
    _startProbe();
    return true;
  }

  Future<void> pullLocations() async {
    if (_rUser == null || _rPass == null) return;
    if (!connected) return; // skip network calls while offline
    _loadingLocations = true;
    notifyListeners();
    try {
      _serverLocations =
          await RedisHelper.readLocations(_rUser!, _rPass!);
      await _saveLocal();
      _saveBgLocations();
    } catch (e) {
      debugPrint('pullLocations failed: $e');
    }
    _loadingLocations = false;
    notifyListeners();
  }

  // Share the uncaught list with the background service for proximity alerts.
  void _saveBgLocations() {
    saveBgLocations(remaining);
  }

  void updateLocation(LatLng loc) {
    currentLocation = loc;
    notifyListeners();
  }

  /// Returns the caught species id on success, or null otherwise.
  Future<String?> catchTerpiez() async {
    final entry = _closestEntry;
    if (entry == null) return null;

    final speciesId = entry['id'] as String;

    _catches.add({
      'lat': entry['lat'],
      'lon': entry['lon'],
      'id': speciesId,
    });
    notifyListeners();

    // Download species details/images the first time this species is caught
    // (only when online; the catch itself is saved locally either way).
    if (!_species.containsKey(speciesId) && connected) {
      await _fetchSpecies(speciesId);
    }

    await _saveLocal();
    _saveBgLocations();
    if (connected) _pushBackup();
    return speciesId;
  }

  /// Resets all game data: clears catches, generates a new user ID, resets
  /// days-active counter, and re-registers with Redis if reachable.
  Future<void> clearData() async {
    _catches.clear();
    _species.clear();
    _appId = _makeUuid();
    _firstRun = DateTime.now();

    await _prefs!.setString('appId', _appId);
    await _prefs!.setString('firstRun', _firstRun!.toIso8601String());

    // Delete cached image files
    if (_filesDir != null) {
      try {
        Directory(_filesDir!).listSync().where((f) => f.path.endsWith('.png')).forEach((f) {
          try { f.deleteSync(); } catch (_) {}
        });
      } catch (_) {}
    }

    await _saveLocal();
    _saveBgLocations();

    if (connected && _rUser != null && _rPass != null) {
      try {
        await RedisHelper.ensureKey(_rUser!, _rPass!, _appId);
      } catch (_) {}
    }

    notifyListeners();
  }

  /// Fetches a species' name, description, and stats, and caches its
  /// full-size image and thumbnail to local files.
  Future<void> _fetchSpecies(String sid) async {
    if (_rUser == null || _rPass == null) return;
    if (!connected) return;
    try {
      final info = await RedisHelper.readSpecies(_rUser!, _rPass!, sid);
      final name = info['name'] ?? 'Unknown';
      final desc = info['description'] ?? '';
      final stats = Map<String, dynamic>.from(info['stats'] ?? {});
      final imgKey = info['image'] ?? '';
      final thumbKey = info['thumbnail'] ?? '';

      String imgFile = '${name}_full.png';
      String thumbFile = '${name}_thumb.png';

      if (imgKey.isNotEmpty) {
        try {
          final b64 =
              await RedisHelper.readImage(_rUser!, _rPass!, imgKey);
          await File('$_filesDir/$imgFile')
              .writeAsBytes(base64Decode(b64));
        } catch (e) { debugPrint('img dl failed: $e'); }
      }

      if (thumbKey.isNotEmpty) {
        try {
          final b64 =
              await RedisHelper.readImage(_rUser!, _rPass!, thumbKey);
          await File('$_filesDir/$thumbFile')
              .writeAsBytes(base64Decode(b64));
        } catch (e) { debugPrint('thumb dl failed: $e'); }
      }

      _species[sid] = {
        'name': name,
        'description': desc,
        'stats': stats,
        'imageFile': imgFile,
        'thumbFile': thumbFile,
      };
      notifyListeners();
    } catch (e) {
      debugPrint('fetchSpecies failed: $e');
    }
  }

  // ── Offline persistence: the whole game state lives in one JSON file ──
  Future<void> _saveLocal() async {
    if (_filesDir == null) return;
    final f = File('$_filesDir/game_state.json');
    await f.writeAsString(jsonEncode({'catches': _catches, 'species': _species, 'locations': _serverLocations}));
  }

  Future<void> _loadLocal() async {
    if (_filesDir == null) return;
    try {
      final f = File('$_filesDir/game_state.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        _catches = List<Map<String, dynamic>>.from(
            (data['catches'] as List).map((e) => Map<String, dynamic>.from(e)));
        final rawSp = Map<String, dynamic>.from(data['species'] ?? {});
        _species = {};
        for (final kv in rawSp.entries) {
          _species[kv.key] = Map<String, dynamic>.from(kv.value);
          if (_species[kv.key]!['stats'] is Map) {
            _species[kv.key]!['stats'] =
                Map<String, dynamic>.from(_species[kv.key]!['stats']);
          }
        }
        if (data['locations'] != null) {
          _serverLocations = List<Map<String, dynamic>>.from(
              (data['locations'] as List).map((e) => Map<String, dynamic>.from(e)));
        }
      }
    } catch (e) {
      debugPrint('loadLocal failed: $e');
    }
  }

  /// Backs up the player's catches to Redis under their account.
  Future<void> _pushBackup() async {
    if (_rUser == null || _rPass == null) return;
    if (!connected) return;
    try {
      await RedisHelper.saveState(_rUser!, _rPass!, _appId, _catches);
    } catch (e) {
      debugPrint('backup failed: $e');
    }
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }
}