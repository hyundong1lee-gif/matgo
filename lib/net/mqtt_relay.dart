import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'relay.dart';

class _Server {
  final String host;
  final int port;
  const _Server(this.host, this.port);
}

/// 공개 MQTT 서버를 중계로 쓴다. 첫 서버에 못 붙으면 다음 서버를 시도한다.
class MqttRelay implements Relay {
  static const _servers = [
    _Server('broker.hivemq.com', 8883),
    _Server('broker.emqx.io', 8883),
  ];

  final String _clientId = 'matgo${List.generate(10, (_) => Random.secure().nextInt(36).toRadixString(36)).join()}';
  final _inC = StreamController<RelayMsg>.broadcast();
  final _onC = StreamController<bool>.broadcast();
  MqttServerClient? _c;

  @override
  Stream<RelayMsg> get incoming => _inC.stream;
  @override
  Stream<bool> get online => _onC.stream;

  @override
  Future<bool> connect() async {
    for (final s in _servers) {
      final c = MqttServerClient.withPort(s.host, _clientId, s.port);
      c.secure = true;
      c.keepAlivePeriod = 20;
      c.autoReconnect = true;
      c.resubscribeOnAutoReconnect = true;
      c.logging(on: false);
      c.setProtocolV311();
      c.onDisconnected = () => _onC.add(false);
      c.onAutoReconnected = () => _onC.add(true);
      c.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .startClean();
      try {
        final st = await c.connect().timeout(const Duration(seconds: 8));
        if (st?.state == MqttConnectionState.connected) {
          _c = c;
          c.updates?.listen(_onUpdates);
          return true;
        }
      } catch (_) {}
      try {
        c.disconnect();
      } catch (_) {}
    }
    return false;
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final e in events) {
      final m = e.payload;
      if (m is! MqttPublishMessage) continue;
      try {
        final text = utf8.decode(m.payload.message.toList());
        _inC.add(RelayMsg(e.topic, text));
      } catch (_) {}
    }
  }

  @override
  void subscribe(String topic) {
    _c?.subscribe(topic, MqttQos.atLeastOnce);
  }

  @override
  void publish(String topic, String payload) {
    final c = _c;
    if (c == null) return;
    if (c.connectionStatus?.state != MqttConnectionState.connected) return;
    final b = MqttClientPayloadBuilder()..addUTF8String(payload);
    c.publishMessage(topic, MqttQos.atLeastOnce, b.payload!);
  }

  @override
  Future<void> close() async {
    final c = _c;
    _c = null;
    try {
      c?.autoReconnect = false;
      c?.disconnect();
    } catch (_) {}
    await _inC.close();
    await _onC.close();
  }
}
