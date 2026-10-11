import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_http_repository.dart';
import 'models.dart';
import 'repository.dart';
import 'settings.dart';
import 'supabase_repository.dart';

/// Build-time configuration (PRD v2 section 7.3 / 9 / 10).
/// Pass with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get hasCloud =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

class ConfigNotifier extends StateNotifier<AppConfig> {
  ConfigNotifier(this._store)
      : super(AppConfig(
          mode: Env.hasCloud ? ConnectionMode.cloud : ConnectionMode.local,
        )) {
    _load();
  }

  final SettingsStore _store;

  Future<void> _load() async {
    final loaded = await _store.load();
    // If cloud is not configured, stay in local mode regardless of stored value.
    state = Env.hasCloud ? loaded : loaded.copyWith(mode: ConnectionMode.local);
  }

  void update(AppConfig config) {
    state = config;
    _store.save(config);
  }

  void setMode(ConnectionMode mode) => update(state.copyWith(mode: mode));
  void setEspIp(String ip) => update(state.copyWith(espIp: ip));
  void setAutoRefresh(bool value) => update(state.copyWith(autoRefresh: value));
  void setIntervalSeconds(int seconds) =>
      update(state.copyWith(refreshSeconds: seconds));
  void setThemeMode(ThemeMode mode) => update(state.copyWith(themeMode: mode));
}

final configProvider =
    StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  return ConfigNotifier(ref.watch(settingsStoreProvider));
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!Env.hasCloud) return null;
  return Supabase.instance.client;
});

/// Signed-in user, if any (cloud mode).
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    return const Stream<AuthState>.empty();
  }
  return client.auth.onAuthStateChange;
});

/// The active repository for the chosen connection mode. Rebuilt when the mode,
/// address, or interval changes.
final repositoryProvider = Provider<ConveyorRepository>((ref) {
  final config = ref.watch(
    configProvider.select((c) => (c.mode, c.espIp, c.refreshSeconds)),
  );

  if (config.$1 == ConnectionMode.local) {
    final repo = LocalHttpRepository(
      baseUrl: config.$2,
      interval: Duration(seconds: config.$3),
    );
    ref.onDispose(repo.dispose);
    return repo;
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw ConveyorException(
        ConveyorError.auth, 'Cloud is not configured for this build.');
  }
  final repo = SupabaseRepository(client);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Live status stream. Disabled when auto-refresh is off (manual refresh only).
final statusProvider = StreamProvider<ConveyorStatus>((ref) {
  final config = ref.watch(configProvider);
  if (!config.autoRefresh) {
    return const Stream<ConveyorStatus>.empty();
  }
  final repo = ref.watch(repositoryProvider);
  return repo.watchStatus();
});

/// Used when automatic refresh is off: a single fetch, re-run on demand.
final manualStatusProvider = FutureProvider<ConveyorStatus>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.fetchStatus();
});
