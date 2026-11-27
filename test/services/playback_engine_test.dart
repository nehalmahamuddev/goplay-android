import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/services/playback/circuit_breaker.dart';
import 'package:goplay/services/playback/connectivity_service.dart';
import 'package:goplay/services/playback/playback_engine.dart';
import 'package:goplay/services/playback/playback_state.dart';

class _FakeConnectivityProbe implements ConnectivityProbe {
  InternetState nextState = InternetState.available;

  @override
  Future<InternetState> checkReachability() async => nextState;
}

class _FakeNativePlayerPort implements NativePlayerPort {
  final List<int> qualityCalls = [];
  final List<Map<String, dynamic>> playCalls = [];

  @override
  Future<void> play(Map<String, dynamic> params) async => playCalls.add(params);

  @override
  Future<void> setQuality(int height) async => qualityCalls.add(height);

  @override
  Future<void> seekTo(int positionMs) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setResizeMode(int mode) async {}

  @override
  Future<Map<dynamic, dynamic>?> getState() async => null;

  @override
  Future<bool?> toggleSubtitles() async => null;

  @override
  void setSpeed(double speed) {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void setChannel(MethodChannel? channel) {}
}

class _FakeKeepAlive implements StreamKeepAlive {
  final List<String> syncedUrls = [];
  bool stopped = false;

  @override
  void syncForUrl(String streamUrl) => syncedUrls.add(streamUrl);

  @override
  void stop() => stopped = true;
}

void main() {
  group('PlaybackEngine', () {
    test('populates PlaybackState.channelId and syncs StreamKeepAlive on loadChannel', () async {
      final probe = _FakeConnectivityProbe();
      final connectivity = ConnectivityService(probe: probe);
      final keepAlive = _FakeKeepAlive();
      final port = _FakeNativePlayerPort();

      final engine = PlaybackEngine(
        connectivityService: connectivity,
        circuitBreaker: CircuitBreaker(),
        nativePort: port,
        keepAlive: keepAlive,
      );

      final channel = Channel(
        id: 'toffee_1',
        name: 'Toffee Live',
        streamUrl: 'https://otte.cache.aiv-cdn.net/stream.m3u8',
      );

      engine.loadChannel(channel);
      expect(engine.state.channelId, 'toffee_1');
      expect(engine.state.phase, PlaybackPhase.preparing);
      expect(keepAlive.syncedUrls, [channel.streamUrl]);

      engine.dispose();
      expect(keepAlive.stopped, isTrue);
    });

    test('fails over sequentially across servers without modulo wrap-around', () {
      final connectivity = ConnectivityService(probe: _FakeConnectivityProbe());
      final port = _FakeNativePlayerPort();
      final engine = PlaybackEngine(
        connectivityService: connectivity,
        circuitBreaker: CircuitBreaker(),
        nativePort: port,
        keepAlive: _FakeKeepAlive(),
      );

      final failoverIndices = <int>[];
      var skippedNext = false;
      engine.onServerFailover = failoverIndices.add;
      engine.onNextChannelRequested = () => skippedNext = true;

      final servers = [
        Channel(id: 'ch_s1', name: 'S1', streamUrl: 'https://1.m3u8'),
        Channel(id: 'ch_s2', name: 'S2', streamUrl: 'https://2.m3u8'),
      ];

      engine.loadChannel(servers[0], servers: servers, activeServerIndex: 0);
      // 403/404 unrecoverable HTTP error triggers immediate skip/failover strategy
      engine.handleNativeError({'message': 'HTTP 404 Not Found', 'httpStatus': 404});
      expect(failoverIndices, [1]);
      expect(skippedNext, isFalse);

      // Load server 1, fail again -> should skip channel, NEVER wrap back to 0!
      engine.loadChannel(servers[1], servers: servers, activeServerIndex: 1);
      engine.handleNativeError({'message': 'HTTP 404 Not Found', 'httpStatus': 404});
      expect(failoverIndices, [1]);
      expect(skippedNext, isTrue);

      engine.dispose();
    });

    test('downgrades manual quality to Auto on repeated stalls', () {
      var now = DateTime.utc(2026, 11, 27, 12, 0, 0);
      final port = _FakeNativePlayerPort();
      final engine = PlaybackEngine(
        connectivityService: ConnectivityService(probe: _FakeConnectivityProbe()),
        circuitBreaker: CircuitBreaker(),
        nativePort: port,
        keepAlive: _FakeKeepAlive(),
        now: () => now,
      );

      var downgraded = false;
      engine.onDowngradedToAuto = () => downgraded = true;

      final channel = Channel(id: 'ch1', name: 'HD TV', streamUrl: 'https://1.m3u8');
      engine.setQualityLabel('1080p');
      engine.loadChannel(channel);

      // Transition to playing so initial playback flag sets
      engine.handleNativeStateEvent({'state': 'playing', 'isPlaying': true});

      // Trigger 3 rapid stalls within 30s
      for (int i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 4));
        engine.handleNativeStateEvent({'state': 'buffering', 'isPlaying': false});
        now = now.add(const Duration(seconds: 1));
        if (i < 2) {
          engine.handleNativeStateEvent({'state': 'playing', 'isPlaying': true});
        }
      }

      expect(downgraded, isTrue);
      expect(engine.currentQuality, 'Auto');
      expect(port.qualityCalls, [-1]);

      engine.dispose();
    });
  });
}
