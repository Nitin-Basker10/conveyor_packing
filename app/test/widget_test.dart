import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_conveyor/models.dart';
import 'package:packing_conveyor/theme.dart';

void main() {
  test('dark palette matches design tokens', () {
    expect(Palette.dark.bg, const Color(0xFF16121B));
    expect(Palette.dark.surface, const Color(0xFF1E1A23));
    expect(Palette.dark.onAccent, const Color(0xFF141019));
    expect(Palette.dark.accent, const Color(0xFFE88A3C));
    expect(Palette.dark.running, const Color(0xFF8FAE8A));
    expect(Palette.dark.fault, const Color(0xFFC25B56));
  });

  test('conveyor state labels follow PRD wording', () {
    expect(ConveyorState.running.label, 'Belt running');
    expect(ConveyorState.pushing.label, 'Moving box sideways');
    expect(ConveyorState.fault.label, 'Fault - belt stopped');
    expect(ConveyorState.fromApi('RETURNING'), ConveyorState.returning);
    expect(ConveyorState.fromApi('nonsense'), ConveyorState.unknown);
  });

  test('ConveyorStatus parses /status payload', () {
    final status = ConveyorStatus.fromJson(const {
      'boxes': 3,
      'total': 23,
      'big': 2,
      'speed': 41.5,
      'rpm': 22.0,
      'set': 65,
      'state': 'RUNNING',
      'fault': '',
    });
    expect(status.boxes, 3);
    expect(status.big, 2);
    expect(status.total, 23);
    expect(status.speed, 41.5);
    expect(status.state, ConveyorState.running);
  });
}
