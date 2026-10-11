import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

/// Cloud mode (PRD v2 sections 5, 7.3, 7.6): reads `device_status` over
/// Supabase Realtime and inserts rows into `commands`.
class SupabaseRepository implements ConveyorRepository {
  SupabaseRepository(this._client, {this.offlineAfter = const Duration(seconds: 10)});

  final SupabaseClient _client;
  final Duration offlineAfter;

  String? _deviceId;
  RealtimeChannel? _channel;

  Future<String> _resolveDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final row = await _client
        .from('devices')
        .select('id')
        .limit(1)
        .maybeSingle();
    if (row == null) {
      throw ConveyorException(
          ConveyorError.offline, 'No device is linked to this account.');
    }
    _deviceId = row['id'] as String;
    return _deviceId!;
  }

  ConveyorStatus _fromRow(Map<String, dynamic> row) {
    final status = ConveyorStatus.fromJson(<String, dynamic>{
      'boxes': row['boxes'],
      'total': row['total'],
      'big': row['big'],
      'speed': row['speed_pps'],
      'rpm': row['rpm'],
      'set': row['set_percent'] ?? 65,
      'state': row['state'],
      'fault': row['fault'],
    });
    return status.copyWith(
      updatedAt: DateTime.tryParse('${row['updated_at']}')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  @override
  Stream<ConveyorStatus> watchStatus() async* {
    final deviceId = await _resolveDeviceId();
    yield* _client
        .from('device_status')
        .stream(primaryKey: ['device_id'])
        .eq('device_id', deviceId)
        .map((rows) {
      if (rows.isEmpty) {
        throw ConveyorException(
            ConveyorError.invalidResponse, ConveyorException.invalidMessage);
      }
      return _fromRow(rows.first);
    });
  }

  @override
  Future<ConveyorStatus> fetchStatus() async {
    final deviceId = await _resolveDeviceId();
    final row = await _client
        .from('device_status')
        .select()
        .eq('device_id', deviceId)
        .maybeSingle();
    if (row == null) {
      throw ConveyorException(
          ConveyorError.offline, 'The conveyor has not reported yet.');
    }
    return _fromRow(row);
  }

  Future<void> _send(String type, {int? value}) async {
    final deviceId = await _resolveDeviceId();
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'type': type,
      'status': 'pending',
    };
    if (value != null) payload['value'] = value;
    final inserted = await _client
        .from('commands')
        .insert(payload)
        .select('id')
        .single();
    final id = inserted['id'];

    // Wait until the device acknowledges it, or give up after 5 s (PRD v2 7.6).
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final row = await _client
          .from('commands')
          .select('status')
          .eq('id', id)
          .maybeSingle();
      final status = row?['status'];
      if (status == 'done') return;
      if (status == 'failed') {
        throw ConveyorException(
            ConveyorError.timeout, 'Command failed. Try again.');
      }
    }
    throw ConveyorException(ConveyorError.timeout, 'Command failed. Try again.');
  }

  @override
  Future<void> start() => _send('start');

  @override
  Future<void> stop() => _send('stop');

  @override
  Future<void> setSpeed(int percent) =>
      _send('speed', value: percent.clamp(20, 100));

  @override
  Future<void> clearFault() => _send('clear_fault');

  @override
  Future<void> refresh() async {
    // Realtime keeps the row fresh; nothing to do here.
  }

  @override
  Future<void> dispose() async {
    await _channel?.unsubscribe();
    _channel = null;
  }
}
