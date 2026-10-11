import 'package:flutter/material.dart';

import 'theme.dart';

/// Conveyor operating states (PRD v2 section 7.2 wording).
enum ConveyorState {
  running,
  paused,
  pushing,
  returning,
  positioning,
  fault,
  unknown;

  static ConveyorState fromApi(String value) {
    switch (value) {
      case 'RUNNING':
        return ConveyorState.running;
      case 'PAUSED':
        return ConveyorState.paused;
      case 'PUSHING':
        return ConveyorState.pushing;
      case 'RETURNING':
        return ConveyorState.returning;
      case 'POSITIONING':
        return ConveyorState.positioning;
      case 'FAULT':
        return ConveyorState.fault;
      default:
        return ConveyorState.unknown;
    }
  }

  String get label {
    switch (this) {
      case ConveyorState.running:
        return 'Belt running';
      case ConveyorState.paused:
        return 'Belt paused';
      case ConveyorState.pushing:
        return 'Moving box sideways';
      case ConveyorState.returning:
        return 'Returning pusher';
      case ConveyorState.positioning:
        return 'Positioning box';
      case ConveyorState.fault:
        return 'Fault - belt stopped';
      case ConveyorState.unknown:
        return 'Unknown';
    }
  }

  Color color(Palette p) {
    switch (this) {
      case ConveyorState.running:
        return p.running;
      case ConveyorState.paused:
      case ConveyorState.unknown:
        return p.paused;
      case ConveyorState.pushing:
      case ConveyorState.returning:
      case ConveyorState.positioning:
        return p.motion;
      case ConveyorState.fault:
        return p.fault;
    }
  }

  bool get isPushMotion =>
      this == ConveyorState.pushing || this == ConveyorState.returning;
}

/// Live conveyor values as returned by `GET /status` and stored in
/// `device_status` (PRD v1 section 5.1 / PRD v2 section 4).
@immutable
class ConveyorStatus {
  const ConveyorStatus({
    required this.boxes,
    required this.total,
    required this.big,
    required this.speed,
    required this.rpm,
    required this.set,
    required this.state,
    required this.fault,
    required this.updatedAt,
  });

  final int boxes; // boxes in the current large box (0-9)
  final int total; // boxes moved since ESP32 restart
  final int big; // completed large boxes
  final double speed; // raw pulses per second
  final double rpm; // roller speed
  final int set; // requested belt speed 20..100
  final ConveyorState state;
  final String fault;
  final DateTime updatedAt;

  static const boxesPerLargeBox = 10;

  factory ConveyorStatus.fromJson(Map<String, dynamic> json) {
    final total = _toInt(json['total']);
    var boxes = _toInt(json['boxes']);
    var big = _toInt(json['big']);
    // Older firmware reports boxes/big as 0 while still counting `total`.
    // Derive them from `total` so the large-box readouts keep working.
    if (total > 0 && boxes == 0 && big == 0) {
      boxes = total % boxesPerLargeBox;
      big = total ~/ boxesPerLargeBox;
    }
    return ConveyorStatus(
      boxes: boxes,
      total: total,
      big: big,
      speed: _toDouble(json['speed']),
      rpm: _toDouble(json['rpm']),
      set: _toInt(json['set']),
      state: ConveyorState.fromApi('${json['state'] ?? ''}'),
      fault: '${json['fault'] ?? ''}',
      updatedAt: DateTime.now(),
    );
  }

  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static double _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  ConveyorStatus copyWith({DateTime? updatedAt}) => ConveyorStatus(
        boxes: boxes,
        total: total,
        big: big,
        speed: speed,
        rpm: rpm,
        set: set,
        state: state,
        fault: fault,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
