import 'dart:convert';
import 'dart:typed_data';

/// 모든 메시지는 {"type": "...", ...필드} 형태의 JSON(UTF-8)이다.
///
/// | type          | 방향            | 필드              |
/// |---------------|-----------------|-------------------|
/// | hello         | 참가자 → 방장   | deviceId          |
/// | welcome       | 방장 → 참가자   | resumed(bool)     |
/// | ping / pong   | 양방향          | -                 |
/// | bye           | 양방향          | reason            |
/// | ready         | 참가자 → 방장   | - (상태 요청)     |
/// | state         | 방장 → 참가자   | 참가자 시점 상태  |
/// | play_card     | 참가자 → 방장   | cardId            |
/// | choose_floor  | 참가자 → 방장   | cardId            |
/// | go_stop       | 참가자 → 방장   | go(bool)          |
/// | new_game      | 참가자 → 방장   | -                 |
/// | _resumed      | 내부 이벤트     | 재연결 성공 알림  |
class Msg {
  static const hello = 'hello';
  static const welcome = 'welcome';
  static const ping = 'ping';
  static const pong = 'pong';
  static const text = 'text';
  static const bye = 'bye';

  static const ready = 'ready';
  static const state = 'state';
  static const playCard = 'play_card';
  static const chooseFloor = 'choose_floor';
  static const goStop = 'go_stop';
  static const newGame = 'new_game';

  static Uint8List encode(String type, [Map<String, dynamic> data = const {}]) {
    return Uint8List.fromList(utf8.encode(jsonEncode({'type': type, ...data})));
  }

  static Map<String, dynamic>? decode(Uint8List bytes) {
    try {
      final v = jsonDecode(utf8.decode(bytes));
      if (v is Map<String, dynamic> && v['type'] is String) return v;
    } catch (_) {}
    return null;
  }
}
