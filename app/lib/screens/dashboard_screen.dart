import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../address_entry.dart';
import '../models.dart';
import '../providers.dart';
import '../repository.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connecting_screen.dart';

/// Telemet dashboard, matching design/screens/dashboard-running 1:1.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _pending;
  String? _message;
  String? _error;
  int? _speedDraft;

  Future<void> _run(String label, Future<void> Function() action) async {
    final config = ref.read(configProvider);
    setState(() {
      _pending = label;
      _error = null;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = '$label sent');
      if (!config.autoRefresh) ref.invalidate(manualStatusProvider);
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted && _message == '$label sent') {
          setState(() => _message = null);
        }
      });
    } on ConveyorException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Command failed. Try again.');
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final config = ref.watch(configProvider);
    final async = config.autoRefresh
        ? ref.watch(statusProvider)
        : ref.watch(manualStatusProvider);
    final status = async.valueOrNull;

    if (status == null && async.isLoading) {
      return ConnectingScreen(
        ip: config.espIp.isEmpty ? 'conveyor' : config.espIp,
      );
    }

    return RefreshIndicator(
      color: p.accent,
      onRefresh: () async {
        await ref.read(repositoryProvider).refresh();
        if (!config.autoRefresh) ref.invalidate(manualStatusProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _HardwareStrip(
            connected: status != null && _online(config, status),
            mode: config.mode,
          ),
          const SizedBox(height: 10),
          if (status != null)
            _dashboard(config, status)
          else
            _problems(async.error),
        ],
      ),
    );
  }

  bool _online(AppConfig config, ConveyorStatus s) {
    if (config.mode == ConnectionMode.local) return true;
    return DateTime.now().toUtc().difference(s.updatedAt).inSeconds < 10;
  }

  Widget _problems(Object? error) {
    final p = context.palette;
    final message = error is ConveyorException
        ? error.message
        : 'Cannot reach the conveyor. Check the address and your network.';
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(Icons.link_off, size: 36, color: p.fault),
          const SizedBox(height: 10),
          Text('Connection problems',
              style: AppText.panelTitle.copyWith(color: p.text)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: p.textSecondary)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ActionButton.secondary(
                  label: 'Change address',
                  onPressed: () => showAddressEntryDialog(
                    context,
                    initial: ref.read(configProvider).espIp,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ActionButton.primary(
                  label: 'Retry',
                  onPressed: () {
                    if (!ref.read(configProvider).autoRefresh) {
                      ref.invalidate(manualStatusProvider);
                    } else {
                      ref.invalidate(repositoryProvider);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboard(AppConfig config, ConveyorStatus s) {
    final p = context.palette;
    final speedTarget = _speedDraft ?? s.set;
    final isFault = s.state == ConveyorState.fault;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isFault) ...[
          _Banner(
            color: p.fault,
            icon: Icons.warning_amber_rounded,
            title: 'Active fault',
            message: s.fault.isEmpty ? 'The belt is stopped.' : s.fault,
          ),
          const SizedBox(height: 10),
        ],
        if (_pending != null) ...[
          _Banner(
            color: p.motion,
            icon: Icons.hourglass_top,
            title: 'Working',
            message: 'Waiting for the conveyor to confirm: $_pending',
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          _Banner(
            color: p.fault,
            icon: Icons.error_outline,
            title: 'Not sent',
            message: _error!,
          ),
          const SizedBox(height: 10),
        ],
        if (_message != null) ...[
          _Banner(
            color: p.running,
            icon: Icons.check_circle_outline,
            title: 'Confirmed',
            message: _message!,
          ),
          const SizedBox(height: 10),
        ],

        // State row between two hairlines.
        _StateRow(state: s.state),

        // Readout table (4 rows).
        _ReadoutTable(status: s),
        const SizedBox(height: 10),

        // Current large box.
        _LargeBoxPanel(status: s),
        const SizedBox(height: 10),

        // Start & Stop side by side.
        Row(
          children: [
            Expanded(
              child: ActionButton.primary(
                label: 'Start',
                subLabel: s.state == ConveyorState.running ? 'Running' : null,
                height: 40,
                onPressed: _pending != null
                    ? null
                    : () => _run('Start',
                        () => ref.read(repositoryProvider).start()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton.secondary(
                label: 'Stop',
                height: 40,
                onPressed: _pending != null
                    ? null
                    : () => _run('Stop',
                        () => ref.read(repositoryProvider).stop()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Speed control.
        _SpeedPanel(
          target: speedTarget,
          draftActive: _speedDraft != null,
          onChanged: (v) => setState(() => _speedDraft = v.round()),
          onCommitted: (v) {
            final target = v.round();
            setState(() => _speedDraft = null);
            _run('Speed $target%',
                () => ref.read(repositoryProvider).setSpeed(target));
          },
        ),
        const SizedBox(height: 10),

        // Utility actions: Clear fault + Refresh.
        Row(
          children: [
            Expanded(
              child: ActionButton.secondary(
                label: 'Clear fault',
                height: 32,
                onPressed: isFault && _pending == null
                    ? () => _run('Clear fault',
                        () => ref.read(repositoryProvider).clearFault())
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton.secondary(
                label: 'Refresh',
                height: 32,
                onPressed: () async {
                  await ref.read(repositoryProvider).refresh();
                  if (!config.autoRefresh) ref.invalidate(manualStatusProvider);
                },
              ),
            ),
          ],
        ),

        // Auto refresh footer.
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.hairline)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('AUTO REFRESH',
                  style: AppText.labelCaps.copyWith(color: p.textSecondary)),
              IndustrialSwitch(
                value: config.autoRefresh,
                onChanged: (v) =>
                    ref.read(configProvider.notifier).setAutoRefresh(v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HardwareStrip extends StatelessWidget {
  const _HardwareStrip({required this.connected, required this.mode});

  final bool connected;
  final ConnectionMode mode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = !connected
        ? 'OFFLINE'
        : (mode == ConnectionMode.cloud ? 'CLOUD' : 'CONNECTED');
    final dotColor =
        !connected ? p.fault : (mode == ConnectionMode.cloud ? p.motion : p.running);
    return Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.precision_manufacturing_outlined,
                size: 18, color: p.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Packing Conveyor',
                  style: AppText.panelTitle
                      .copyWith(fontSize: 14, color: p.text)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: p.inset,
              child: Row(
                children: [
                  Container(width: 7, height: 7, color: dotColor),
                  const SizedBox(width: 6),
                  Text(label,
                      style: AppText.labelCaps.copyWith(color: dotColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.state});

  final ConveyorState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = state.color(p);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.hairline),
          bottom: BorderSide(color: p.hairline),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(state.label,
              style: AppText.panelTitle
                  .copyWith(fontSize: 15, color: p.text)),
        ],
      ),
    );
  }
}

class _ReadoutTable extends StatelessWidget {
  const _ReadoutTable({required this.status});

  final ConveyorStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        children: [
          _row(context, 'Roller speed',
              status.rpm.toStringAsFixed(1), 'RPM', p.text),
          _row(context, 'Belt setting',
              status.set.toString(), '%', p.accent),
          _row(context, 'Boxes moved',
              status.total.toString(), null, p.text),
          _row(context, 'Large boxes filled',
              status.big.toString(), null, p.text),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, String? unit,
      Color valueColor) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(),
              style: AppText.labelCaps.copyWith(color: p.textSecondary)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: AppText.readoutSecondary
                      .copyWith(fontSize: 14, color: valueColor)),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(unit,
                      style:
                          AppText.labelCaps.copyWith(color: p.textSecondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LargeBoxPanel extends StatelessWidget {
  const _LargeBoxPanel({required this.status});

  final ConveyorStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      radius: 2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('CURRENT LARGE BOX',
                    style: AppText.labelCaps
                        .copyWith(color: p.textSecondary)),
                Text('${status.boxes} / ${ConveyorStatus.boxesPerLargeBox}',
                    style: AppText.readoutSecondary
                        .copyWith(fontSize: 13, color: p.text)),
              ],
            ),
            const SizedBox(height: 8),
            LargeBoxBar(filled: status.boxes),
          ],
        ),
      ),
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({
    required this.target,
    required this.draftActive,
    required this.onChanged,
    required this.onCommitted,
  });

  final int target;
  final bool draftActive;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommitted;

  static const _ticks = [20, 40, 60, 80, 100];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      radius: 2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SPEED',
                    style: AppText.labelCaps
                        .copyWith(color: p.textSecondary)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$target',
                        style: AppText.dispNumeric
                            .copyWith(fontSize: 32, color: p.text)),
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text('%',
                          style: AppText.readoutSecondary
                              .copyWith(color: p.accent)),
                    ),
                  ],
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: p.accent,
                inactiveTrackColor: p.raised,
                thumbColor: p.accent,
                overlayColor: p.accent.withValues(alpha: 0.15),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                min: 20,
                max: 100,
                divisions: 80,
                value: target.toDouble().clamp(20, 100),
                label: '$target%',
                onChanged: onChanged,
                onChangeEnd: onCommitted,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in _ticks)
                  GestureDetector(
                    onTap: () => onCommitted(t.toDouble()),
                    child: Text(t.toString(),
                        style: AppText.readoutMicro
                            .copyWith(color: p.textFaint)),
                  ),
              ],
            ),
            if (draftActive)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('PENDING — RELEASE TO APPLY',
                    textAlign: TextAlign.center,
                    style:
                        AppText.labelMicro.copyWith(color: p.accent)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(),
                    style: AppText.labelCaps.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(message, style: AppText.body.copyWith(color: p.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}