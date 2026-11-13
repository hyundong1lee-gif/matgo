/// 인터넷 대전에서 두 폰 사이를 이어 주는 중계 서버의 최소 기능.
/// 실제로는 공개 MQTT 서버를 쓰고 테스트에서는 메모리 가짜를 쓴다.
class RelayMsg {
  final String topic;
  final String payload;
  const RelayMsg(this.topic, this.payload);
}

abstract class Relay {
  Stream<RelayMsg> get incoming;

  /// 서버와의 연결이 살아 있는지 (끊기면 false 복구되면 true)
  Stream<bool> get online;

  /// 서버에 연결한다. 실패하면 false.
  Future<bool> connect();

  void subscribe(String topic);
  void publish(String topic, String payload);
  Future<void> close();
}
