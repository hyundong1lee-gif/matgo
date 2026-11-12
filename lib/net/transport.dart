/// 게임 코드는 이 인터페이스만 본다.
/// 나중에 가짜 상대(봇)를 만들 때도 이 인터페이스를 구현하면 된다.
enum LinkState {
  idle,
  advertising,
  discovering,
  connecting,
  connected,
  reconnecting,
  failed,
}

class Room {
  final String endpointId;
  final String name;
  const Room(this.endpointId, this.name);
}

abstract class GameTransport {
  Stream<LinkState> get state;
  Stream<List<Room>> get rooms;

  /// 상대가 보낸 게임/텍스트 메시지. 재연결되면 {'type': '_resumed'}가 한 번 들어온다.
  Stream<Map<String, dynamic>> get messages;
  Stream<String> get logs;

  LinkState get current;
  bool get isHost;

  Future<void> host();
  Future<void> startSearch();
  Future<void> join(Room room);
  Future<bool> send(String type, [Map<String, dynamic> data = const {}]);

  /// 재연결 테스트용으로 연결을 강제로 끊는다.
  Future<void> debugDrop();
  Future<void> close();
}
