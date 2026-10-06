# Terpiez

A location-based mobile game built with Flutter. Walk around in the real world, find Terpiez hiding nearby on the map, and shake your phone to catch them. Played by 50+ students.

Built as a self-directed project during a mobile development course at the University of Maryland.

<!-- Screenshots: add map.png, catch.png, and collection.png to a screenshots/ folder -->
<p float="left">
  <img src="screenshots/map.png" width="250" />
  <img src="screenshots/catch.png" width="250" />
  <img src="screenshots/collection.png" width="250" />
</p>

## Features

- **Live map:** OpenStreetMap view that follows your GPS position and shows the nearest uncaught Terpiez
- **Shake to catch:** the accelerometer detects a shake; catches only count within 10 m of a Terpiez
- **Background alerts:** a foreground service checks your location every 20 seconds and notifies you when a Terpiez is within 20 m, even with the app closed (tapping the alert opens the map)
- **Works offline:** all game state is saved locally as JSON, so progress is never lost when the connection drops
- **Connection monitoring:** the app pings the server every 10 seconds and shows a banner when the connection is lost or restored
- **Cloud backup:** catches sync to a Redis (RedisJSON) server, with a 1-second timeout on every call so the UI never hangs
- **Collection & details:** browse caught species with images, stats, descriptions, and a map of every catch location
- **Secure login:** credentials are stored in encrypted device storage
- **Polish:** catch sound effect (toggleable), physics-based particle animation, and portrait/landscape layouts

## Tech Stack

| Area | Tools |
|---|---|
| App | Flutter, Dart, Provider (state management) |
| Maps & location | flutter_map, OpenStreetMap, geolocator, latlong2 |
| Backend | Redis with the RedisJSON module |
| Device | sensors_plus (accelerometer), flutter_local_notifications, flutter_background_service, audioplayers |
| Storage | shared_preferences, flutter_secure_storage, local JSON files |

## Project Structure

```
lib/
├── main.dart                 # Entry point, tab layout, settings drawer
├── game_model.dart           # Core game state, distance math, offline save, sync
├── redis_helper.dart         # All Redis network calls
├── finder_screen.dart        # Map + shake-to-catch gameplay
├── list_screen.dart          # Caught species collection
├── detail_screen.dart        # Species details + catch-location map
├── stats_screen.dart         # Player stats
├── background_service.dart   # Background proximity checks
├── notification_service.dart # Notification channels + tap handling
├── credentials_dialog.dart   # Login form
├── settings_model.dart       # Saved user preferences
└── sound_service.dart        # Catch sound effect
```

## Running Locally

```bash
git clone https://github.com/EvenEstifanos/terpiez.git
cd terpiez
flutter pub get
flutter run --dart-define=REDIS_HOST=your.redis.host --dart-define=REDIS_PORT=6379
```

Requires the Flutter SDK, an Android device or emulator with location enabled, and a Redis server with RedisJSON. The game reads this data layout:

| Key | Contents |
|---|---|
| `locations` | JSON array of spawn points: `{ "lat", "lon", "id" }` |
| `terpiez` | JSON object of species by id: `{ name, description, stats, image, thumbnail }` |
| `images` | JSON object of base64-encoded PNGs by image id |
| `<username>` | Player catch backups, keyed by app install id |

## What I Learned

Building Terpiez taught me how to keep a mobile app reliable on a flaky network (local-first saving, timeouts, and connection probing), how to run location checks in a background service, and how to use device sensors and notifications in a real-world, cross-platform app.

## Author

**Even Estifanos** · [GitHub](https://github.com/EvenEstifanos) · [LinkedIn](https://www.linkedin.com/in/even-estifanos-2ab18b2a6/)
