import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local_http_repository.dart';
import '../providers.dart';
import '../repository.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connecting_screen.dart';

/// Connect screen, matching design/screens/connect.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

enum _Link { idle, connecting, connected }

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _ipController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _Link _link = _Link.idle;
  String? _error;
  bool _authBusy = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _ipController.text = ref.read(configProvider).espIp;
  }

  @override
  void dispose() {
    _ipController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connectLocal() async {
    final ip = LocalHttpRepository.normalizeBaseUrl(_ipController.text);
    if (ip.isEmpty) {
      setState(() {
        _error = 'Enter the IP address shown on the OLED.';
        _link = _Link.idle;
      });
      return;
    }
    final attempt = ++_attempt;
    setState(() {
      _link = _Link.connecting;
      _error = null;
    });
    final probe = LocalHttpRepository(baseUrl: ip);
    try {
      await probe.fetchStatus();
      if (!mounted || attempt != _attempt) return;
      setState(() => _link = _Link.connected);
      final notifier = ref.read(configProvider.notifier);
      notifier.setEspIp(ip);
      notifier.setMode(ConnectionMode.local);
    } on ConveyorException catch (e) {
      if (mounted && attempt == _attempt) {
        setState(() {
          _error = e.message;
          _link = _Link.idle;
        });
      }
    } finally {
      await probe.dispose();
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
      if (mounted) {
        ref.read(configProvider.notifier).setMode(ConnectionMode.cloud);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not sign in. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final config = ref.watch(configProvider);

    if (_link == _Link.connecting) {
      return ConnectingScreen(
        ip: LocalHttpRepository.normalizeBaseUrl(_ipController.text),
        onCancel: () {
          if (mounted) {
            setState(() {
              _attempt++;
              _link = _Link.idle;
            });
          }
        },
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _rackHeader(p),
            const SizedBox(height: 14),

            // Address bay.
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SubHeaderStrip(
                    title: 'ESP32 IP ADDRESS',
                    trailing: 'NET_OCTET',
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.inset,
                            border: Border.all(
                                color: _link == _Link.connecting
                                    ? p.accent
                                    : p.hairline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lan_outlined,
                                  size: 18, color: p.textFaint),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _ipController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: AppText.readoutSecondary
                                      .copyWith(color: p.text),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: '192.168.1.50',
                                    hintStyle: AppText.readoutSecondary
                                        .copyWith(color: p.textFaint),
                                  ),
                                ),
                              ),
                              _BlinkCursor(
                                active: _ipController.text.isEmpty &&
                                    _link != _Link.connecting,
                                color: p.accent,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ActionButton.primary(
                          label: _link == _Link.connecting
                              ? 'Connecting...'
                              : 'Connect',
                          height: 44,
                          onPressed:
                              _link == _Link.connecting ? null : _connectLocal,
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: config.espIp.isEmpty
                                ? null
                                : () => setState(() {
                                      _ipController.text = config.espIp;
                                    }),
                            icon: Icon(Icons.visibility_outlined,
                                size: 14, color: p.accent),
                            label: Text('USE ADDRESS SHOWN ON OLED',
                                style: AppText.labelCaps
                                    .copyWith(color: p.accent)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (config.espIp.isNotEmpty) ...[
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SubHeaderStrip(
                      title: 'RECENT ADDRESS',
                      trailing: 'NV_MEM:01',
                    ),
                    InkWell(
                      onTap: () =>
                          setState(() => _ipController.text = config.espIp),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.history, size: 16, color: p.textFaint),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(config.espIp,
                                  style: AppText.readoutSecondary
                                      .copyWith(color: p.text)),
                            ),
                            const TagChip(label: 'Tap to fill'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Diagnostic grid.
            Row(
              children: [
                Expanded(
                  child: _DiagTile(
                    label: 'WIFI BUS',
                    value: '2.4',
                    unit: 'GHZ / CH6',
                    p: p,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DiagTile(
                    label: 'CONVEYOR ID',
                    value: 'CV-04',
                    unit: 'STATION B',
                    p: p,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Instruction notice.
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: p.textFaint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Read the IP address from the conveyor OLED screen. '
                        'Ensure this phone is on the same Wi-Fi network as the '
                        'ESP32.',
                        style: AppText.labelCaps
                            .copyWith(color: p.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Panel(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 18, color: p.fault),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: AppText.body.copyWith(color: p.text)),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (Env.hasCloud) ...[
              const SizedBox(height: 14),
              _cloudPanel(p),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rackHeader(Palette p) {
    final statusLabel = switch (_link) {
      _Link.idle => 'NOT CONNECTED',
      _Link.connecting => 'CONNECTING',
      _Link.connected => 'CONNECTED',
    };
    final dot = switch (_link) {
      _Link.idle => p.paused,
      _Link.connecting => p.accent,
      _Link.connected => p.running,
    };
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, color: dot),
                      const SizedBox(width: 8),
                      Text(statusLabel,
                          style: AppText.labelCaps
                              .copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
                Text('PORT // 8080',
                    style: AppText.readoutMicro.copyWith(color: p.textFaint)),
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: p.hairline),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text('Packing Conveyor',
                      style: AppText.panelTitle.copyWith(color: p.text)),
                ),
                Text('ESP32-S3 CORE',
                    style: AppText.labelCaps.copyWith(color: p.textFaint)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cloudPanel(Palette p) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SubHeaderStrip(title: 'CLOUD ACCOUNT', trailing: 'SUPABASE'),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sign in to control the conveyor remotely.',
                    style: AppText.body.copyWith(color: p.textSecondary)),
                const SizedBox(height: 10),
                InputWell(
                  controller: _emailController,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                InputWell(controller: _passwordController, hint: 'Password'),
                const SizedBox(height: 10),
                ActionButton.primary(
                  label: _authBusy ? 'Signing in...' : 'Sign in',
                  height: 40,
                  onPressed: _authBusy ? null : _signIn,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagTile extends StatelessWidget {
  const _DiagTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.p,
  });

  final String label;
  final String value;
  final String unit;
  final Palette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.labelMicro.copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style:
                      AppText.readoutSecondary.copyWith(color: p.text)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(unit,
                    style:
                        AppText.labelMicro.copyWith(color: p.textFaint)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlinkCursor extends StatefulWidget {
  const _BlinkCursor({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor> {
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _on ? 1 : 0,
      child: Container(width: 8, height: 16, color: widget.color),
    );
  }
}