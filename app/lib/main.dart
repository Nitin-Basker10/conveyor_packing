import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers.dart';
import 'screens/connect_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_shell.dart';
import 'screens/settings_screen.dart';
import 'screens/states_screen.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.hasCloud) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }
  runApp(const ProviderScope(child: PackingConveyorApp()));
}

class PackingConveyorApp extends ConsumerWidget {
  const PackingConveyorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(configProvider.select((c) => c.themeMode));
    return MaterialApp(
      title: 'Packing Conveyor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final client = ref.watch(supabaseClientProvider);
    // Rebuild when auth changes.
    ref.watch(authStateProvider);

    final ready = config.mode == ConnectionMode.local
        ? config.espIp.isNotEmpty
        : client?.auth.currentSession != null;

    if (!ready) return const ConnectScreen();
    return const HomeShell(
      telemet: DashboardScreen(),
      states: StatesScreen(),
      config: SettingsScreen(),
    );
  }
}
