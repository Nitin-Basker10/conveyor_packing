import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'repository.dart';

/// One telemetry sample used by the speed graph.
@immutable
class SpeedSample {
  const SpeedSample({
    required this.time,
    required this.rpm,
    required this.pps,
    required this.set,
    required this.state,
  });

  final DateTime time;
  final double rpm;
  final double pps;
  final int set;
  final ConveyorState state;
}

/// One entry in the conveyor status report / event log.
@immutable
class ConveyorEvent {
  const ConveyorEvent({
    required this.time,
    required this.message,
    required this.state,
  });

  final DateTime time;
  final String message;
  final ConveyorState state;
}

@immutable
class ConveyorHistory {
  const ConveyorHistory({this.samples = const [], this.events = const []});

  final List<SpeedSample> samples;
  final List<ConveyorEvent> events;

  static const maxSamples = 60;
  static const maxEvents = 50;
}

/// Accumulates live samples and derived events from the status stream.
class HistoryNotifier extends StateNotifier<ConveyorHistory> {
  HistoryNotifier(ConveyorRepository repo) : super(const ConveyorHistory()) {
    _sub = repo.watchStatus().listen(
      add,
      onError: (_) {},
    );
  }

  StreamSubscription<ConveyorStatus>? _sub;
  ConveyorStatus? _last;

  void add(ConveyorStatus s) {
    final samples = [...state.samples, SpeedSample(
      time: DateTime.now(),
      rpm: s.rpm,
      pps: s.speed,
      set: s.set,
      state: s.state,
    )];
    if (samples.length > ConveyorHistory.maxSamples) samples.removeAt(0);

    final events = [...state.events];
    void log(String message) {
      events.insert(0, ConveyorEvent(
        time: DateTime.now(),
        message: message,
        state: s.state,
      ));
    }

    final prev = _last;
    if (prev == null) {
      log('LINK ESTABLISHED · ${s.state.label}');
    } else {
      if (prev.state != s.state) log('STATE → ${s.state.label}');
      if (s.total > prev.total) log('BOX SORTED · ${s.boxes}/${ConveyorStatus.boxesPerLargeBox}');
      if (s.big > prev.big) log('LARGE BOX FILLED · #${s.big}');
      if (s.fault.isNotEmpty && s.fault != prev.fault) {
        log('FAULT · ${s.fault}');
      }
    }
    if (events.length > ConveyorHistory.maxEvents) {
      events.removeRange(ConveyorHistory.maxEvents, events.length);
    }

    _last = s;
    state = ConveyorHistory(samples: samples, events: events);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, ConveyorHistory>((ref) {
  final repo = ref.watch(repositoryProvider);
  return HistoryNotifier(repo);
});
