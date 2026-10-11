import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'repository.dart';

/// Local mode (PRD v1): talks to the ESP32 HTTP API on the same Wi-Fi.
class LocalHttpRepository implements ConveyorRepository {
  LocalHttpRepository({
    required String baseUrl,
    Duration interval = const Duration(seconds: 1),
  })  : _baseUrl = normalizeBaseUrl(baseUrl),
        _interval = interval;

  final http.Client _client = http.Client();
  final _controller = StreamController<ConveyorStatus>.broadcast();
  final String _baseUrl;
  Duration _interval;
  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;

  static const _timeout = Duration(seconds: 4);

  String get baseUrl => _baseUrl;

  /// Accepts `192.168.1.50`, `http://192.168.1.50`, `192.168.1.50/` and stores
  /// `http://192.168.1.50` (PRD v1 section 3).
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!value.toLowerCase().startsWith('http://') &&
        !value.toLowerCase().startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  @override
  Stream<ConveyorStatus> watchStatus() {
    _start();
    return _controller.stream;
  }

  void _start() {
    if (_timer != null) return;
    _poll();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  void setInterval(Duration interval) {
    _interval = interval;
    if (_timer != null) {
      _timer!.cancel();
      _timer = Timer.periodic(_interval, (_) => _poll());
    }
  }

  /// Poll a little faster while the pusher is moving so state changes feel live
  /// (PRD v1 section 6).
  void _scheduleNext(ConveyorStatus? last) {
    final fast = last != null &&
        (last.state == ConveyorState.pushing ||
            last.state == ConveyorState.returning);
    final wanted = fast ? const Duration(milliseconds: 400) : _interval;
    if (wanted == _interval) return;
    _timer?.cancel();
    _timer = Timer.periodic(wanted, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_inFlight || _disposed) return;
    _inFlight = true;
    try {
      final status = await _getStatus();
      if (!_disposed) {
        _controller.add(status);
        _scheduleNext(status);
      }
    } on ConveyorException catch (e) {
      if (!_disposed) _controller.addError(e);
    } finally {
      _inFlight = false;
    }
  }

  Future<ConveyorStatus> _getStatus() => _request('/status');

  /// One-shot status fetch, used to validate a connection before entering the
  /// dashboard (PRD v1 section 3).
  @override
  Future<ConveyorStatus> fetchStatus() => _getStatus();

  Future<ConveyorStatus> _request(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    http.Response resp;
    try {
      resp = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw ConveyorException(
          ConveyorError.timeout, ConveyorException.timeoutMessage);
    } on SocketException {
      throw ConveyorException(
          ConveyorError.unreachable, ConveyorException.unreachableMessage);
    } on http.ClientException {
      throw ConveyorException(
          ConveyorError.unreachable, ConveyorException.unreachableMessage);
    }

    if (resp.statusCode != 200) {
      String text = '';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['error'] is String) {
          text = decoded['error'] as String;
        }
      } catch (_) {}
      throw ConveyorException(
          ConveyorError.http,
          text.isNotEmpty
              ? text
              : 'The conveyor returned HTTP ${resp.statusCode}.');
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw ConveyorException(
            ConveyorError.invalidResponse, ConveyorException.invalidMessage);
      }
      return ConveyorStatus.fromJson(decoded);
    } on FormatException {
      throw ConveyorException(
          ConveyorError.invalidResponse, ConveyorException.invalidMessage);
    }
  }

  Future<void> _command(String path) async {
    final status = await _request(path);
    if (!_disposed) _controller.add(status);
  }

  @override
  Future<void> start() => _command('/start');

  @override
  Future<void> stop() => _command('/stop');

  @override
  Future<void> setSpeed(int percent) {
    final clamped = percent.clamp(20, 100);
    return _command('/speed?percent=$clamped');
  }

  @override
  Future<void> clearFault() => _command('/clear-fault');

  @override
  Future<void> refresh() => _poll();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    await _controller.close();
  }
}
