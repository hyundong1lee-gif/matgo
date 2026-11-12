import '../net/messages.dart';
import 'matgo_game.dart';
import 'scoring.dart';

List<int> _ints(dynamic v) => (v as List).map((e) => e as int).toList();

/// 한 플레이어 시점의 게임 상태. 상대 패와 남은 더미의 내용은 들어 있지 않다.
class ViewState {
  final int me; // 0 방장 1 참가자
  final int seq;
  final int turn;
  final Phase phase;
  final List<int> hand; // 내 패
  final int oppHandCount; // 상대 패는 장수만
  final List<int> floor;
  final int stockCount; // 더미는 장수만
  final List<List<int>> captured; // 먹은 패는 공개 정보 (인덱스는 0 방장 1 참가자)
  final List<int> goCount;
  final List<int> scores;
  final List<int> options;
  final List<int> lastHands; // 이번 턴에 낸 손패
  final List<int> shakes; // 플레이어별 폭탄/흔들기 횟수
  final int? lastStock;
  final int? lastBy;
  final List<GameEvent> events;
  final GameResult? result;

  int? get lastHand => lastHands.isEmpty ? null : lastHands.first;

  const ViewState({
    required this.me,
    required this.seq,
    required this.turn,
    required this.phase,
    required this.hand,
    required this.oppHandCount,
    required this.floor,
    required this.stockCount,
    required this.captured,
    required this.goCount,
    required this.scores,
    required this.options,
    required this.lastHands,
    required this.shakes,
    required this.lastStock,
    required this.lastBy,
    required this.events,
    required this.result,
  });

  factory ViewState.of(MatgoGame g, int me, int seq) {
    return ViewState(
      me: me,
      seq: seq,
      turn: g.turn,
      phase: g.phase,
      hand: List<int>.of(g.hands[me])..sort(),
      oppHandCount: g.hands[1 - me].length,
      floor: List<int>.of(g.floor),
      stockCount: g.stock.length,
      captured: [List<int>.of(g.captured[0]), List<int>.of(g.captured[1])],
      goCount: List<int>.of(g.goCount),
      scores: [scoreOf(g.captured[0]).total, scoreOf(g.captured[1]).total],
      options: List<int>.of(g.ctx.options),
      lastHands: List<int>.of(g.lastHands),
      shakes: List<int>.of(g.shakeCount),
      lastStock: g.lastStock,
      lastBy: g.lastBy,
      events: List<GameEvent>.of(g.events),
      result: g.result,
    );
  }

  Map<String, dynamic> toJson() => {
        'proto': kProtocol,
        'me': me,
        'seq': seq,
        'turn': turn,
        'phase': phase.index,
        'hand': hand,
        'oppHandCount': oppHandCount,
        'floor': floor,
        'stockCount': stockCount,
        'captured': captured,
        'goCount': goCount,
        'scores': scores,
        'options': options,
        'lastHands': lastHands,
        'shakes': shakes,
        'lastStock': lastStock,
        'lastBy': lastBy,
        'events': events.map((e) => e.toJson()).toList(),
        'result': result?.toJson(),
      };

  factory ViewState.fromJson(Map<String, dynamic> j) {
    return ViewState(
      me: j['me'] as int,
      seq: j['seq'] as int,
      turn: j['turn'] as int,
      phase: Phase.values[j['phase'] as int],
      hand: _ints(j['hand']),
      oppHandCount: j['oppHandCount'] as int,
      floor: _ints(j['floor']),
      stockCount: j['stockCount'] as int,
      captured: (j['captured'] as List).map(_ints).toList(),
      goCount: _ints(j['goCount']),
      scores: _ints(j['scores']),
      options: _ints(j['options']),
      lastHands: _ints(j['lastHands']),
      shakes: _ints(j['shakes']),
      lastStock: j['lastStock'] as int?,
      lastBy: j['lastBy'] as int?,
      events: (j['events'] as List)
          .map((e) => GameEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      result: j['result'] == null
          ? null
          : GameResult.fromJson(j['result'] as Map<String, dynamic>),
    );
  }
}
