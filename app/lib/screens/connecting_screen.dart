import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Handshake / connecting screen, matching design/screens/connecting 1:1.
class ConnectingScreen extends StatefulWidget {
  const ConnectingScreen({
    super.key,
    required this.ip,
    this.onCancel,
  });

  final String ip;
  final VoidCallback? onCancel;

  @override
  State<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends State<ConnectingScreen> {
  Timer? _dots;
  Timer? _progress;
  int _dotCount = 1;
  double _elapsed = 4.2;
  bool _aborted = false;

  static const double _totalTimeout = 10.0;

  @override
  void initState() {
    super.initState();
    _dots = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) setState(() => _dotCount = (_dotCount % 3) + 1);
    });
    _progress = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _aborted) return;
      setState(() {
        _elapsed += 0.1;
        if (_elapsed > _totalTimeout) _elapsed = 0;
      });
    });
  }

  @override
  void dispose() {
    _dots?.cancel();
    _progress?.cancel();
    super.dispose();
  }

  void _abort() {
    _dots?.cancel();
    _progress?.cancel();
    setState(() => _aborted = true);
    widget.onCancel?.call();
  }

  double get _progressFraction => (_elapsed / _totalTimeout).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dots = '.' * _dotCount;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Panel(
                  radius: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Rack header bar.
                      Container(
                        color: p.raised,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            Container(width: 6, height: 6, color: p.textFaint),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('SYS_BUS // COMM_LINK_V4',
                                  style: AppText.labelCaps
                                      .copyWith(color: p.textSecondary)),
                            ),
                            Text('ESP32-S3',
                                style: AppText.readoutMicro
                                    .copyWith(color: p.textFaint)),
                            const SizedBox(width: 8),
                            Text('CH_01',
                                style: AppText.readoutMicro
                                    .copyWith(color: p.accent)),
                          ],
                        ),
                      ),

                      // Recessed display well.
                      Expanded(
                        child: Container(
                          color: p.inset,
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    color: p.raised,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                            width: 6,
                                            height: 6,
                                            color: p.textFaint),
                                        const SizedBox(width: 6),
                                        Text(
                                          _aborted
                                              ? 'STATUS: HANDSHAKE ABORTED'
                                              : 'STATUS: HANDSHAKE IN PROGRESS',
                                          style: AppText.labelCaps.copyWith(
                                              color: p.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text('CONNECTING TO',
                                      style: AppText.labelCaps.copyWith(
                                          color: p.textFaint,
                                          letterSpacing: 0.16)),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.ip.replaceFirst(
                                              'http://', ''),
                                          textAlign: TextAlign.center,
                                          style: AppText.dispNumeric
                                              .copyWith(fontSize: 30),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(dots,
                                          style: AppText.dispNumeric
                                              .copyWith(
                                                  fontSize: 30,
                                                  color: p.textFaint)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('PORT // 8080   |   TCP-RAW',
                                      style: AppText.readoutSecondary
                                          .copyWith(color: p.textSecondary)),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: 300,
                                    child: Row(
                                      children: List.generate(8, (i) {
                                        return Expanded(
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                                right: i == 7 ? 0 : 4),
                                            child: Container(
                                              height: 4,
                                              color: i < 3
                                                  ? p.accent
                                                  : p.raised,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: 300,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: Container(
                                        height: 4,
                                        color: p.raised,
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor:
                                              _aborted ? 0 : _progressFraction,
                                          child: Container(color: p.accent),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 300,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _aborted
                                              ? 'HANDSHAKE ABORTED'
                                              : 'TIMEOUT: ${_elapsed.toStringAsFixed(1)}s / ${_totalTimeout.toStringAsFixed(1)}s',
                                          style: AppText.readoutMicro
                                              .copyWith(color: p.textFaint),
                                        ),
                                        Text('PKT: 03/08',
                                            style: AppText.readoutMicro
                                                .copyWith(color: p.textFaint)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: 300,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      color: p.surface,
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('TX SYN_SENT',
                                                  style:
                                                      AppText.readoutMicro.copyWith(
                                                          color: p.textFaint)),
                                              Text('ACK_WAIT',
                                                  style:
                                                      AppText.readoutMicro.copyWith(
                                                          color: p.running)),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('MAC: 7C:DF:A1:88:14:B2',
                                                  style:
                                                      AppText.readoutMicro.copyWith(
                                                          color: p.textFaint)),
                                              Text('RSSI: -58 dBm',
                                                  style:
                                                      AppText.readoutMicro.copyWith(
                                                          color: p.textFaint)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Action tray.
                      Container(
                        color: p.raised,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Material(
                                color: p.surface,
                                borderRadius: BorderRadius.circular(4),
                                child: InkWell(
                                  onTap: _aborted ? null : _abort,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    height: 40,
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.close,
                                            size: 16, color: p.text),
                                        const SizedBox(width: 6),
                                        Text(
                                          _aborted
                                              ? 'ABORTING...'
                                              : 'CANCEL HANDSHAKE',
                                          style: AppText.buttonText
                                              .copyWith(color: p.text),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('MANUAL ABORT RETURNS TO DIAGNOSTIC SELECTOR',
                                textAlign: TextAlign.center,
                                style: AppText.labelMicro
                                    .copyWith(color: p.textFaint)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('CONVEYOR NODE // PACK-FEED-MOD04',
                      style:
                          AppText.labelMicro.copyWith(color: p.textFaint)),
                  Text('STATUS: UNASSIGNED',
                      style:
                          AppText.labelMicro.copyWith(color: p.textFaint)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
