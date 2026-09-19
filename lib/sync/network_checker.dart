import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lightweight, non-blocking network availability detector.
///
/// Complies with `docs/Rules.md` §16 and the offline-first sync requirement:
/// - Runs an initial check on app launch.
/// - Polls conservatively (default every 90 seconds) rather than hammering.
/// - Hard timeout (2.5 seconds) on probes so an offline or firewall-dropped
///   network never hangs the application or delays the UI.
class NetworkAvailabilityChecker {
  final Duration checkInterval;
  final String? customHost;
  final Future<bool> Function()? probeOverride;

  Timer? _timer;
  bool _isOnline = false;
  final _controller = StreamController<bool>.broadcast();

  NetworkAvailabilityChecker({
    this.checkInterval = const Duration(seconds: 90),
    this.customHost,
    this.probeOverride,
  });

  bool get isOnline => _isOnline;

  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Starts periodic connectivity probing and performs an immediate check.
  void start() {
    _timer?.cancel();
    checkNow();
    _timer = Timer.periodic(checkInterval, (_) => checkNow());
  }

  /// Stops background probing.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Probes network connectivity immediately and updates listeners if state changed.
  Future<bool> checkNow() async {
    final connected = await _probe();
    if (connected != _isOnline) {
      _isOnline = connected;
      _controller.add(connected);
    }
    return connected;
  }

  Future<bool> _probe() async {
    if (probeOverride != null) {
      try {
        return await probeOverride!();
      } catch (_) {
        return false;
      }
    }

    try {
      final host = customHost ?? '1.1.1.1';
      final lookup = await InternetAddress.lookup(host)
          .timeout(const Duration(milliseconds: 2500));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      // Any error (SocketException, TimeoutException, etc.) implies offline.
      return false;
    }
  }

  @visibleForTesting
  void forceState(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      _controller.add(online);
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
