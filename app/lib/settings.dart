import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConnectionMode { cloud, local }

/// Address of the conveyor on the local network. Empty by default so the app
/// opens on the address-entry screen and the operator types the IP shown on the
/// OLED (it changes with every network/DHCP lease).
const String kDefaultEspIp = '';

@immutable
class AppConfig {
  const AppConfig({
    this.mode = ConnectionMode.cloud,
    this.espIp = kDefaultEspIp,
    this.autoRefresh = true,
    this.refreshSeconds = 1,
    this.themeMode = ThemeMode.dark,
  });

  final ConnectionMode mode;
  final String espIp;
  final bool autoRefresh;
  final int refreshSeconds; // 1, 2 or 5
  final ThemeMode themeMode;

  Duration get interval => Duration(seconds: refreshSeconds);

  AppConfig copyWith({
    ConnectionMode? mode,
    String? espIp,
    bool? autoRefresh,
    int? refreshSeconds,
    ThemeMode? themeMode,
  }) {
    return AppConfig(
      mode: mode ?? this.mode,
      espIp: espIp ?? this.espIp,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      refreshSeconds: refreshSeconds ?? this.refreshSeconds,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

/// Persists AppConfig in shared_preferences (PRD v1 section 8 / PRD v2 7.7).
class SettingsStore {
  static const _kMode = 'mode';
  static const _kIp = 'espIp';
  static const _kAuto = 'autoRefresh';
  static const _kInterval = 'refreshSeconds';
  static const _kTheme = 'themeMode';

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(
      mode: ConnectionMode.values[
          prefs.getInt(_kMode) ?? ConnectionMode.cloud.index],
      espIp: prefs.getString(_kIp) ?? kDefaultEspIp,
      autoRefresh: prefs.getBool(_kAuto) ?? true,
      refreshSeconds: prefs.getInt(_kInterval) ?? 1,
      themeMode: ThemeMode.values[prefs.getInt(_kTheme) ?? ThemeMode.dark.index],
    );
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMode, config.mode.index);
    await prefs.setString(_kIp, config.espIp);
    await prefs.setBool(_kAuto, config.autoRefresh);
    await prefs.setInt(_kInterval, config.refreshSeconds);
    await prefs.setInt(_kTheme, config.themeMode.index);
  }
}
