/// 게임 코드는 이 인터페이스만 본다.
/// 나중에 가짜 상대(봇)를 만들 때도 이 인터페이스를 구현하면 된다.
/// 연결이 끊긴 뒤 다시 붙기를 기다려 주는 시간
const Duration kReconnectWindow = Duration(seconds: 60);

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

  /// 상대가 보낸 게임/텍스트 메시지. 방장 쪽에서는 보낸 자리 번호가 `_from` 으로 붙는다.
  /// 재연결되면 {'type': '_resumed'} 가 한 번 들어온다(방장은 `_from` 포함).
  Stream<Map<String, dynamic>> get messages;
  Stream<String> get logs;

  LinkState get current;

  /// 인터넷 대전의 방 코드 (근처 연결은 null)
  String? get roomCode;
  bool get isHost;

  /// 방의 인원 (2 또는 3). 방장이 정하고 참가자는 입장할 때 받는다.
  int get players;

  /// 내 자리 번호. 방장 0 참가자 1부터.
  int get mySeat;

  /// 방장 쪽에서 지금까지 들어온 참가자 수
  int get joined;

  Future<void> host({int players = 2});
  Future<void> startSearch();
  Future<void> join(Room room);

  /// 방장은 모든 참가자에게 참가자는 방장에게 보낸다.
  Future<bool> send(String type, [Map<String, dynamic> data = const {}]);

  /// 방장이 특정 참가자(자리 번호)에게만 보낸다.
  Future<bool> sendTo(int seat, String type, [Map<String, dynamic> data = const {}]);

  /// 재연결 테스트용으로 연결을 강제로 끊는다.
  Future<void> debugDrop();
  Future<void> close();
}
