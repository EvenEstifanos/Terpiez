// main.dart
//
// App entry point. Sets up notifications and the background location
// service, loads saved settings, then builds the three-tab UI
// (Stats / Finder / List) with a settings drawer.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'background_service.dart';
import 'credentials_dialog.dart';
import 'finder_screen.dart';
import 'game_model.dart';
import 'list_screen.dart';
import 'notification_service.dart';
import 'settings_model.dart';
import 'stats_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notifications and request permission.
  final notifGranted = await initNotifications();

  // Set up the background location service (always configure, only start if
  // notification permission was granted).
  await initBackgroundService();
  if (notifGranted) {
    await startBackgroundService();
  } else {
    debugPrint('[main] Skipping background service: notification permission denied');
  }

  // If the app was launched by tapping a proximity notification, jump to the
  // finder tab immediately.
  final initialTab = await getInitialTabFromNotification();
  if (initialTab != null) tabIndexNotifier.value = initialTab;

  // Load persisted settings before the widget tree is built.
  final settings = SettingsModel();
  await settings.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameModel()..boot()),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Terpiez',
      debugShowCheckedModeBanner: false,
      home: Shell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shell: shows loading spinner → credentials dialog → main app
// ---------------------------------------------------------------------------

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameModel>(
      builder: (context, model, _) {
        if (!model.ready) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!model.loggedIn) {
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Terpiez', style: TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFF800000),
                iconTheme: const IconThemeData(color: Colors.white),
                bottom: const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(icon: Icon(Icons.show_chart), text: 'Stats'),
                    Tab(icon: Icon(Icons.search), text: 'Finder'),
                    Tab(icon: Icon(Icons.list), text: 'List'),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('Terpiez found: 0'),
                        Text('Days Active: 0'),
                      ],
                    ),
                  ),
                  Container(
                    color: Colors.black54,
                    child: const CredentialsDialog(),
                  ),
                ],
              ),
            ),
          );
        }

        if (model.serverLocations.isEmpty && !model.loadingLocations) {
          WidgetsBinding.instance.addPostFrameCallback((_) => model.pullLocations());
        }

        return const HomePage();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HomePage: tab controller driven by tabIndexNotifier + settings drawer
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool? _lastConnected;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: tabIndexNotifier.value,
    );
    tabIndexNotifier.addListener(_syncTab);
  }

  void _syncTab() {
    if (mounted && _tabController.index != tabIndexNotifier.value) {
      _tabController.animateTo(tabIndexNotifier.value);
    }
  }

  @override
  void dispose() {
    tabIndexNotifier.removeListener(_syncTab);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameModel>(
      builder: (context, model, _) {
        // Show snackbar when connection state changes.
        if (_lastConnected == null) {
          _lastConnected = model.connected;
        } else if (_lastConnected != model.connected) {
          _lastConnected = model.connected;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            if (model.connected) {
              messenger.showSnackBar(const SnackBar(
                content: Text('Connection to server restored',
                    style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ));
            } else {
              messenger.showSnackBar(const SnackBar(
                content: Text('Lost connection to Redis server',
                    style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ));
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Terpiez', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF800000),
            iconTheme: const IconThemeData(color: Colors.white),
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(icon: Icon(Icons.show_chart), text: 'Stats'),
                Tab(icon: Icon(Icons.search), text: 'Finder'),
                Tab(icon: Icon(Icons.list), text: 'List'),
              ],
            ),
          ),
          drawer: _buildDrawer(context, model),
          body: TabBarView(
            controller: _tabController,
            children: const [
              StatsScreen(),
              FinderScreen(),
              ListScreen(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, GameModel model) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              color: const Color(0xFF800000),
              child: const Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Sound toggle
            Consumer<SettingsModel>(
              builder: (context, settings, _) {
                return SwitchListTile(
                  title: const Text('Sound Effects'),
                  subtitle: const Text('In-app sounds (catch jingle)'),
                  value: settings.soundEnabled,
                  activeThumbColor: const Color(0xFF800000),
                  activeTrackColor: const Color(0xFF800000).withAlpha(128),
                  onChanged: (val) => settings.setSoundEnabled(val),
                );
              },
            ),

            const Divider(),

            // Clear data
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Clear Data',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text('Reset all Terpiez, stats & user ID'),
              onTap: () => _confirmClearData(context, model),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearData(BuildContext context, GameModel model) async {
    // Capture navigator and messenger before the async gap.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will permanently delete all caught Terpiez, reset your days-active '
          'counter, and generate a new user ID. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    navigator.pop(); // close drawer
    await model.clearData();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('All data cleared. New user ID generated.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
