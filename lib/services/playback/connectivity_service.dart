import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Internet reachability states.
///
/// [ConnectivityService] reports these after verifying actual internet access
/// via lightweight HTTP HEAD requests — never trusting the OS connectivity
/// signal alone.
enum InternetState {
  /// Device has verified internet access.
  available,

  /// No network interface or verified unreachable.
  noInternet,

  /// Connected to a network but intercepted by a captive portal.
  captivePortal,

  /// DNS resolution is failing.
  dnsFailure,

  /// Not yet determined.
  unknown,
}

/// Seam isolating network reachability probes from [ConnectivityService].
abstract class ConnectivityProbe {
  Future<InternetState> checkReachability();
}

/// Production probe adapter executing lightweight HTTP HEAD requests.
class HttpConnectivityProbe implements ConnectivityProbe {
  const HttpConnectivityProbe();

  static const _probeUrls = [
    'https://connectivitycheck.gstatic.com/generate_204', // Google
    'https://clients3.google.com/generate_204', // Google fallback
    'https://cp.cloudflare.com/', // Cloudflare
  ];

  @override
  Future<InternetState> checkReachability() async {
    for (final url in _probeUrls) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.headUrl(Uri.parse(url));
        final response = await request.close().timeout(
              const Duration(seconds: 5),
            );
        await response.drain<void>();
        client.close(force: true);

        final code = response.statusCode;

        // 204 or 200 = real internet
        if (code == 204 || code == 200) {
          return InternetState.available;
        }

        // Redirect (302/301/307) = likely captive portal intercepting traffic
        if (code >= 300 && code < 400) {
          return InternetState.captivePortal;
        }
      } on SocketException catch (e) {
        if (e.osError?.message.contains('host lookup') == true ||
            e.message.contains('Failed host lookup') ||
            e.message.contains('nodename nor servname')) {
          return InternetState.dnsFailure;
        }
        continue;
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    return InternetState.noInternet;
  }
}

/// Detects real internet availability using an injected [ConnectivityProbe].
class ConnectivityService {
  ConnectivityService({
    ConnectivityProbe? probe,
    Duration pollInterval = const Duration(seconds: 10),
  })  : _probe = probe ?? const HttpConnectivityProbe(),
        _pollInterval = pollInterval;

  final ConnectivityProbe _probe;
  final Duration _pollInterval;

  /// Current verified internet state.
  InternetState get state => _stateNotifier.value;

  /// Listenable notifier for UI / state-machine binding.
  ValueNotifier<InternetState> get stateNotifier => _stateNotifier;

  final ValueNotifier<InternetState> _stateNotifier =
      ValueNotifier(InternetState.unknown);

  /// Stream that emits only when the state actually changes.
  Stream<InternetState> get stream => _controller.stream;
  final StreamController<InternetState> _controller =
      StreamController<InternetState>.broadcast();

  Timer? _pollingTimer;
  bool _disposed = false;

  /// Start monitoring. Call once at app startup or when entering the player.
  Future<void> initialize() async {
    if (_disposed) return;
    await checkNow();
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollInterval, (_) {
      if (!_disposed) checkNow();
    });
  }

  /// Perform an on-demand reachability check. Returns the verified state.
  Future<InternetState> checkNow() async {
    if (_disposed) return InternetState.unknown;

    try {
      final result = await _probe.checkReachability();
      _updateState(result);
      return result;
    } catch (_) {
      _updateState(InternetState.noInternet);
      return InternetState.noInternet;
    }
  }

  void _updateState(InternetState newState) {
    if (_disposed) return;
    if (_stateNotifier.value != newState) {
      _stateNotifier.value = newState;
      _controller.add(newState);
      debugPrint('ConnectivityService: state → $newState');
    }
  }

  /// Whether internet is currently believed to be offline.
  bool get isOffline =>
      state == InternetState.noInternet ||
      state == InternetState.dnsFailure ||
      state == InternetState.captivePortal;

  /// Clean up resources.
  void dispose() {
    _disposed = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _stateNotifier.dispose();
    _controller.close();
  }
}
