import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history.dart';
import '../models.dart';
import '../providers.dart';
import '../repository.dart';
import '../speed_graph.dart';
import '../theme.dart';
import '../widgets.dart';

/// States / status report view: live telemetry, speed graph and event log.
class StatesScreen extends ConsumerStatefulWidget {
  const StatesScreen({super.key});

  @override
  ConsumerState<StatesScreen> createState() => _StatesScreenState();
}

class _StatesScreenState extends ConsumerState<StatesScreen> {
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final config = ref.watch(configProvider);
    final async = config.autoRefresh
        ? ref.watch(statusProvider)
        : ref.watch(manualStatusProvider);
    final status = async.valueOrNull;
    final history = ref.watch(historyProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SystemBanner(online: status != null),
        const SizedBox(height: 10),
        if (status == null && async.isLoading)
          _loading(p)
        else if (status == null)
          _unavailable(p, async.error)
        else ...[
          if (status.state == ConveyorState.fault) ...[
            _Annunciator(
              status: status,
              clearing: _clearing,
              onClear: _clearing ? null : _clearFault,
            ),
            const SizedBox(height: 10),
          ],
          _StatusReport(status: status),
          const SizedBox(height: 10),
          _SpeedPanel(status: status, samples: history.samples),
          const SizedBox(height: 10),
          _PackingLogic(status: status),
          const SizedBox(height: 10),
          _EventLog(events: history.events),
          const SizedBox(height: 10),
          _StateMatrix(state: status.state),
        ],
      ],
    );
  }

  Future<void> _clearFault() async {
    setState(() => _clearing = true);
    try {
      await ref.read(repositoryProvider).clearFault();
    } on ConveyorException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Widget _loading(Palette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: CircularProgressIndicator(color: p.accent, strokeWidth: 2),
        ),
      );

  Widget _unavailable(Palette p, Object? error) => Panel(
        padding: const EdgeInsets.all(14),
        child: Text(
          error is ConveyorException
              ? error.message
              : 'No telemetry available.',
          style: AppText.body.copyWith(color: p.textSecondary),
        ),
      );
}

String _clock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class _SystemBanner extends StatelessWidget {
  const _SystemBanner({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      radius: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(width: 8, height: 8, color: online ? p.running : p.fault),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RACK-01 // CORE_STATE_BUS',
                      style: AppText.labelCaps.copyWith(color: p.textSecondary)),
                  Text('ESP32-S3 @ 240MHz · RTOS ACTIVE',
                      style: AppText.readoutMicro.copyWith(color: p.textFaint)),
                ],
              ),
            ),
            TagChip(
                label: online ? 'Nominal sync' : 'No sync',
                color: online ? p.running : p.fault),
          ],
        ),
      ),
    );
  }
}

class _StatusReport extends StatelessWidget {
  const _StatusReport({required this.status});

  final ConveyorStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = status.state.color(p);
    final age = DateTime.now().difference(status.updatedAt.toLocal()).inSeconds;
    return Panel(
      radius: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: p.raised,
            child: Row(
              children: [
                Icon(Icons.assignment_outlined, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('STATUS REPORT',
                      style: AppText.panelTitle
                          .copyWith(fontSize: 13, color: p.text)),
                ),
                Text('LIVE', style: AppText.readoutMicro.copyWith(color: p.running)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(width: 10, height: 10, color: color),
                    const SizedBox(width: 8),
                    Text(status.state.label.toUpperCase(),
                        style: AppText.panelTitle
                            .copyWith(fontSize: 15, color: p.text)),
                    const Spacer(),
                    Text('${age}s AGO',
                        style:
                            AppText.readoutMicro.copyWith(color: p.textFaint)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Current large box',
                        value:
                            '${status.boxes} / ${ConveyorStatus.boxesPerLargeBox}',
                        sub: status.boxes >= ConveyorStatus.boxesPerLargeBox
                            ? 'CAPACITY REACHED'
                            : 'FILLING',
                        valueColor: status.boxes >= ConveyorStatus.boxesPerLargeBox
                            ? p.running
                            : p.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Metric(
                        label: 'Large boxes filled',
                        value: status.big.toString(),
                        sub: 'PALLET BATCH',
                        valueColor: p.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Metric(
                        label: 'Boxes moved',
                        value: status.total.toString(),
                        sub: 'FEEDER TALLY',
                        valueColor: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.status, required this.samples});

  final ConveyorStatus status;
  final List<SpeedSample> samples;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxRpm = samples.isEmpty
        ? status.rpm
        : samples.map((s) => s.rpm).fold<double>(0, (a, b) => b > a ? b : a);
    return Panel(
      radius: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: p.raised,
            child: Row(
              children: [
                Icon(Icons.show_chart, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('SPEED GRAPH // ROLLER',
                      style: AppText.panelTitle
                          .copyWith(fontSize: 13, color: p.text)),
                ),
                Text('${samples.length} PTS',
                    style: AppText.readoutMicro.copyWith(color: p.textFaint)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(status.rpm.toStringAsFixed(1),
                        style: AppText.dispNumeric.copyWith(fontSize: 34)),
                    const SizedBox(width: 4),
                    Text('RPM',
                        style: AppText.labelCaps.copyWith(color: p.accent)),
                    const Spacer(),
                    Text('BELT ${status.speed.toStringAsFixed(1)} PPS',
                        style:
                            AppText.readoutMicro.copyWith(color: p.textFaint)),
                    const SizedBox(width: 10),
                    Text('SET ${status.set}%',
                        style:
                            AppText.readoutMicro.copyWith(color: p.textFaint)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SpeedGraph(samples: samples),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('PEAK ${maxRpm.toStringAsFixed(0)} RPM',
                        style: AppText.labelMicro.copyWith(color: p.textFaint)),
                    Text('WINDOW 60 SAMPLES',
                        style: AppText.labelMicro.copyWith(color: p.textFaint)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.events});

  final List<ConveyorEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      radius: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: p.raised,
            child: Row(
              children: [
                Icon(Icons.history_toggle_off, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('STATUS REPORT // EVENT LOG',
                      style: AppText.panelTitle
                          .copyWith(fontSize: 13, color: p.text)),
                ),
                Text('${events.length}',
                    style: AppText.readoutMicro.copyWith(color: p.textFaint)),
              ],
            ),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('No events yet — start the belt to record activity.',
                  style: AppText.body.copyWith(color: p.textFaint)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: events.length,
                itemBuilder: (context, i) {
                  final e = events[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(top: BorderSide(color: p.hairline)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          color: e.state.color(p),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.message,
                              style: AppText.body.copyWith(color: p.text)),
                        ),
                        Text(_clock(e.time),
                            style: AppText.readoutMicro
                                .copyWith(color: p.textFaint)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PackingLogic extends StatelessWidget {
  const _PackingLogic({required this.status});

  final ConveyorStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final full = status.boxes >= ConveyorStatus.boxesPerLargeBox;
    return Panel(
      radius: 4,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 16, color: p.textFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('PACKING LOGIC // LARGE BOX CYCLE',
                      style: AppText.labelCaps
                          .copyWith(color: p.textSecondary)),
                ),
                TagChip(
                    label: full ? 'Batch complete' : 'In progress',
                    color: full ? p.running : p.textFaint),
              ],
            ),
            const SizedBox(height: 10),
            LargeBoxBar(filled: status.boxes),
          ],
        ),
      ),
    );
  }
}

class _Annunciator extends StatelessWidget {
  const _Annunciator({
    required this.status,
    required this.clearing,
    required this.onClear,
  });

  final ConveyorStatus status;
  final bool clearing;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      radius: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: p.raised,
            child: Row(
              children: [
                Icon(Icons.warning, size: 18, color: p.fault),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('ANNUNCIATOR // CRITICAL ALARM',
                      style: AppText.panelTitle
                          .copyWith(fontSize: 13, color: p.text)),
                ),
                Text('TRIP LEVEL 1',
                    style: AppText.readoutMicro.copyWith(color: p.fault)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(width: 12, height: 12, color: p.fault),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('FAULT — BELT STOPPED',
                      style: AppText.panelTitle
                          .copyWith(fontSize: 15, color: p.text)),
                ),
                TagChip(label: 'Latched', color: p.fault),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Container(
              decoration: BoxDecoration(
                color: p.inset,
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: p.fault),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ALARM 0x04: MOTOR STALL DETECTED',
                              style: AppText.readoutSecondary
                                  .copyWith(fontSize: 13, color: p.fault)),
                          const SizedBox(height: 4),
                          Text(
                            status.fault.isEmpty
                                ? 'Conveyor belt drive stalled or optical '
                                    'sensor timeout. Check the belt path.'
                                : status.fault,
                            style: AppText.body.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: p.raised,
            child: ActionButton.primary(
              label: clearing
                  ? 'Sending bus reset (0x04)...'
                  : 'Acknowledge & clear fault',
              height: 42,
              onPressed: onClear,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateMatrix extends StatelessWidget {
  const _StateMatrix({required this.state});

  final ConveyorState state;

  static const _rows = [
    (ConveyorState.paused, 'Belt Paused', 'STATE 00 // IDLE',
        'ACTUATOR BUS: MOTOR SLEEP · BRAKE CHARGED'),
    (ConveyorState.pushing, 'Moving Box Sideways', 'STATE 01 // TRANSFER',
        'LATERAL PUSHER EXTENDING (STROKE 120MM)'),
    (ConveyorState.returning, 'Returning Pusher', 'STATE 02 // RETRACT',
        'LIMIT SWITCH HOME VERIFICATION'),
    (ConveyorState.positioning, 'Positioning Box', 'STATE 03 // ALIGN',
        'MICRO-STEPPING STAGING CONVEYOR TO GATE #04'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      radius: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: p.raised,
            child: Row(
              children: [
                Icon(Icons.schema, size: 18, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('STATE MACHINE MATRIX',
                      style: AppText.panelTitle
                          .copyWith(fontSize: 13, color: p.text)),
                ),
                Text('SEQ_MAP_V2',
                    style: AppText.readoutMicro.copyWith(color: p.textFaint)),
              ],
            ),
          ),
          for (var i = 0; i < _rows.length; i++)
            _StateMachineRow(
              state: _rows[i].$1,
              title: _rows[i].$2,
              code: _rows[i].$3,
              detail: _rows[i].$4,
              active: state == _rows[i].$1,
              last: i == _rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _StateMachineRow extends StatelessWidget {
  const _StateMachineRow({
    required this.state,
    required this.title,
    required this.code,
    required this.detail,
    required this.active,
    required this.last,
  });

  final ConveyorState state;
  final String title;
  final String code;
  final String detail;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = state.color(p);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? p.inset : Colors.transparent,
        border: last ? null : Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: active ? color : p.paused,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: AppText.panelTitle.copyWith(
                      fontSize: 14,
                      color: active ? color : p.textFaint,
                    )),
              ),
              TagChip(label: code, color: color, border: active),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(detail,
                style: AppText.labelMicro.copyWith(color: p.textFaint)),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: AppText.labelMicro.copyWith(color: p.textFaint)),
          const SizedBox(height: 4),
          Text(value,
              style: AppText.readoutSecondary
                  .copyWith(fontSize: 22, color: valueColor)),
          const SizedBox(height: 2),
          Text(sub,
              style: AppText.labelMicro.copyWith(color: p.textFaint)),
        ],
      ),
    );
  }
}
