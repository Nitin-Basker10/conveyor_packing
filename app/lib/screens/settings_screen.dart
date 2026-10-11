import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local_http_repository.dart';
import '../models.dart';
import '../providers.dart';
import '../repository.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Config / settings, matching design/screens/settings.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _ipController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _authBusy = false;
  bool _ipBusy = false;
  String? _ipError;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: ref.read(configProvider).espIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connectIp() async {
    final ip = LocalHttpRepository.normalizeBaseUrl(_ipController.text);
    if (ip.isEmpty) {
      setState(() => _ipError = 'Enter the IP address shown on the OLED.');
      return;
    }
    setState(() {
      _ipBusy = true;
      _ipError = null;
    });
    final probe = LocalHttpRepository(baseUrl: ip);
    try {
      await probe.fetchStatus();
      if (!mounted) return;
      ref.read(configProvider.notifier)
        ..setEspIp(ip)
        ..setMode(ConnectionMode.local);
      FocusScope.of(context).unfocus();
      _toast('Connected to ${ip.replaceFirst('http://', '')}');
    } on ConveyorException catch (e) {
      if (mounted) setState(() => _ipError = e.message);
    } catch (_) {
      if (mounted) setState(() => _ipError = 'Could not reach that address.');
    } finally {
      await probe.dispose();
      if (mounted) setState(() => _ipBusy = false);
    }
  }

  Future<void> _signIn() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _authBusy = true);
    try {
      await client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      ref.read(configProvider.notifier).setMode(ConnectionMode.cloud);
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not sign in. Check your connection.');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final config = ref.watch(configProvider);
    final notifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Calibration meta bar.
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settings',
                      style: AppText.panelTitle.copyWith(color: p.text)),
                  Text('DEVICE CONFIG',
                      style: AppText.labelMicro
                          .copyWith(color: p.textFaint)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: p.inset,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 13, color: p.accent),
                  const SizedBox(width: 4),
                  Text('SLOT-05 // RW',
                      style: AppText.readoutMicro.copyWith(color: p.accent)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Network configuration.
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubHeaderStrip(
                title: 'Network configuration',
                trailing: 'PORT 8080',
                icon: Icons.lan_outlined,
                tint: p.textSecondary,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ESP32 IP ADDRESS',
                        style: AppText.labelMicro.copyWith(color: p.textFaint)),
                    const SizedBox(height: 6),
                    InputWell(
                      controller: _ipController,
                      hint: '192.168.1.50',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      suffix: (config.espIp.isNotEmpty)
                          ? Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: 6,
                                      height: 6,
                                      color: p.running),
                                  const SizedBox(width: 5),
                                  Text('SAVED',
                                      style: AppText.labelMicro
                                          .copyWith(color: p.running)),
                                ],
                              ),
                            )
                          : null,
                      onSubmitted: (_) => _ipBusy ? null : _connectIp(),
                    ),
                    if (_ipError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, size: 15, color: p.fault),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_ipError!,
                                style: AppText.labelCaps
                                    .copyWith(color: p.fault, height: 1.3)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ActionButton.primary(
                            label:
                                _ipBusy ? 'Testing link...' : 'Test & connect',
                            height: 36,
                            onPressed: _ipBusy ? null : _connectIp,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetricBox(
                            label: 'Target',
                            value: config.espIp.isEmpty
                                ? '—'
                                : config.espIp.replaceFirst('http://', ''),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Polling & refresh.
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubHeaderStrip(
                title: 'Polling & refresh',
                trailing: 'SYS-TMR',
                icon: Icons.sync_alt,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.inset,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AUTOMATIC REFRESH',
                                    style: AppText.labelCaps
                                        .copyWith(color: p.text)),
                                Text('CONTINUOUS SENSOR STREAM',
                                    style: AppText.labelMicro
                                        .copyWith(color: p.textFaint)),
                              ],
                            ),
                          ),
                          IndustrialSwitch(
                            value: config.autoRefresh,
                            onChanged: notifier.setAutoRefresh,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('REFRESH INTERVAL',
                            style:
                                AppText.labelMicro.copyWith(color: p.textFaint)),
                        Text('CURRENT: ${config.refreshSeconds} SEC',
                            style: AppText.readoutMicro
                                .copyWith(color: p.accent)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SegmentedSelector<int>(
                      value: config.refreshSeconds,
                      onChanged: notifier.setIntervalSeconds,
                      options: const [
                        (1, '1 s', null),
                        (2, '2 s', null),
                        (5, '5 s', null),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Display theme.
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubHeaderStrip(
                title: 'Display theme',
                trailing: 'OLED COMPLIANT',
                icon: Icons.contrast,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('THEME MODE',
                        style: AppText.labelMicro.copyWith(color: p.textFaint)),
                    const SizedBox(height: 6),
                    SegmentedSelector<ThemeMode>(
                      value: config.themeMode == ThemeMode.light
                          ? ThemeMode.light
                          : ThemeMode.dark,
                      onChanged: notifier.setThemeMode,
                      options: const [
                        (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                        (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Packaging batch.
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubHeaderStrip(
                title: 'Packaging batch',
                trailing: 'READ-ONLY',
                icon: Icons.inventory_2_outlined,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.inset,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BOXES PER LARGE BOX',
                                style: AppText.labelCaps
                                    .copyWith(color: p.text)),
                            Text('Set on the conveyor',
                                style: AppText.labelMicro
                                    .copyWith(color: p.textFaint)),
                          ],
                        ),
                      ),
                      Text('${ConveyorStatus.boxesPerLargeBox}',
                          style: AppText.readoutSecondary
                              .copyWith(fontSize: 18, color: p.accent)),
                      const SizedBox(width: 4),
                      Text('PCS',
                          style: AppText.labelMicro
                              .copyWith(color: p.textFaint)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Bench diagnostics.
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SubHeaderStrip(
                title: 'Bench diagnostics',
                trailing: 'READY',
                icon: Icons.terminal,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _kvRow(context, 'Link mode',
                        config.mode == ConnectionMode.cloud
                            ? 'CLOUD / SUPABASE'
                            : 'LOCAL WI-FI',
                        p.text),
                    _divider(p),
                    _kvRow(context, 'Target',
                        config.espIp.isEmpty
                            ? 'Linked device'
                            : config.espIp.replaceFirst('http://', ''),
                        p.accent),
                    _divider(p),
                    _kvRow(context, 'Auto refresh',
                        config.autoRefresh
                            ? 'ON · ${config.refreshSeconds}s'
                            : 'MANUAL',
                        config.autoRefresh ? p.running : p.textFaint),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (Env.hasCloud) _cloudPanel(p, ref),
      ],
    );
  }

  Widget _kvRow(BuildContext context, String label, String value, Color color) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(),
              style: AppText.labelMicro.copyWith(color: p.textFaint)),
          Text(value, style: AppText.readoutSecondary.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _divider(Palette p) =>
      Container(height: 1, color: p.hairline);

  Widget _cloudPanel(Palette p, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final email = client?.auth.currentUser?.email;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubHeaderStrip(
            title: 'Cloud account',
            trailing: email == null ? 'SIGNED OUT' : 'SIGNED IN',
            icon: Icons.cloud_outlined,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('CONNECTION MODE',
                    style: AppText.labelMicro.copyWith(color: p.textFaint)),
                const SizedBox(height: 6),
                SegmentedSelector<ConnectionMode>(
                  value: ref.read(configProvider).mode,
                  onChanged: ref.read(configProvider.notifier).setMode,
                  options: const [
                    (ConnectionMode.cloud, 'Cloud', Icons.cloud_outlined),
                    (ConnectionMode.local, 'Local', Icons.wifi_outlined),
                  ],
                ),
                const SizedBox(height: 12),
                if (email == null) ...[
                  InputWell(
                    controller: _emailController,
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  InputWell(
                    controller: _passwordController,
                    hint: 'Password',
                  ),
                  const SizedBox(height: 10),
                  ActionButton.primary(
                    label: _authBusy ? 'Signing in...' : 'Sign in',
                    height: 40,
                    onPressed: _authBusy ? null : _signIn,
                  ),
                ] else ...[
                  _kvRow(context, 'Signed in as', email, p.text),
                  const SizedBox(height: 8),
                  ActionButton.secondary(
                    label: 'Sign out',
                    height: 36,
                    onPressed: () async {
                      await client?.auth.signOut();
                      ref.read(configProvider.notifier).setMode(
                          Env.hasCloud
                              ? ConnectionMode.cloud
                              : ConnectionMode.local);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: AppText.labelMicro.copyWith(color: p.textFaint)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppText.readoutMicro.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}