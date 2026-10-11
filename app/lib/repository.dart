import 'models.dart';

/// Error kinds with the wording from PRD v1 section 7.
enum ConveyorError { unreachable, timeout, invalidResponse, http, offline, auth }

class ConveyorException implements Exception {
  ConveyorException(this.kind, this.message);

  final ConveyorError kind;
  final String message;

  @override
  String toString() => message;

  static const unreachableMessage =
      'Cannot reach the conveyor. Make sure the phone and ESP32 are on the same '
      'Wi-Fi network, then check the IP address on the OLED screen.';
  static const timeoutMessage =
      'The conveyor did not reply. Check its power and Wi-Fi connection.';
  static const invalidMessage =
      'The conveyor sent an unexpected reply. Refresh the connection.';
}

/// One interface used by all screens. Both cloud and local modes implement it,
/// so the UI never knows which one is active (PRD v2 section 7.3).
abstract class ConveyorRepository {
  /// Live values. Emits an error (ConveyorException) through the stream on
  /// connection problems.
  Stream<ConveyorStatus> watchStatus();

  /// One-shot status fetch (used to validate a connection and for manual mode).
  Future<ConveyorStatus> fetchStatus();

  Future<void> start();
  Future<void> stop();
  Future<void> setSpeed(int percent);
  Future<void> clearFault();

  /// Force an immediate status fetch (Refresh button).
  Future<void> refresh();

  Future<void> dispose();
}
