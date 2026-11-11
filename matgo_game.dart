import 'dart:math';

import 'cards.dart';
import 'config.dart';
import 'scoring.dart';

enum Phase { playCard, chooseFloorHand, chooseFloorStock, goStop, ended }

enum HandCase { none, unmatched, paired, pairedFromTwo, captured }

class GameEvent {
  final int p; // 행동한 플레이어(0 방장 1 참가자) 나가리는 -1
  final String code;
  const GameEvent(this.p, this.code);

  Map<String, dynamic> toJson() => {'p': p, 'e': code};

  factory GameEvent.fromJson(Map<String, dynamic> j) =>
      GameEvent(j['p'] as int, j['e'] as String);
}

class TurnCtx {
  int? hand;
  int? partner;
  int? other;
  int? stockCard;
  HandCase hcase = HandCase.none;
  List<int> options = [];
}

class GameResult {
  final int winner; // -1 = 나가리
  final int points;
  final List<String> lines;
  final List<List<String>> details; // 플레이어별 족보 내역

  const GameResult(this.winner, this.points, this.lines, this.details);

  Map<String, dynamic> toJson() => {
        'winner': winner,
        'points': points,
        'lines': lines,
        'details': details,
      };

  factory GameResult.fromJson(Map<String, dynamic> j) => GameResult(
        j['winner'] as int,
        j['points'] as int,
        (j['lines'] as List).map((e) => e as String).toList(),
        (j['details'] as List)
            .map((d) => (d as List).map((e) => e as String).toList())
            .toList(),
      );
}

/// 2인 맞고 규칙 엔진. UI와 통신을 모르는 순수 Dart 클래스다.
/// 방장 폰에서만 만들어서 쓴다.
class MatgoGame {
  MatgoGame({int first = 0, Random? rng})
      : _rng = rng ?? Random(),
        firstPlayer = first {
    turn = first;
    _deal();
  }

  /// 테스트용. stock의 마지막 원소가 더미의 맨 위다.
  MatgoGame.custom({
    required List<int> hand0,
    required List<int> hand1,
    required List<int> floor,
    required List<int> stock,
    List<int> captured0 = const [],
    List<int> captured1 = const [],
    int first = 0,
    Random? rng,
  })  : _rng = rng ?? Random(),
        firstPlayer = first {
    turn = first;
    hands[0].addAll(hand0);
    hands[1].addAll(hand1);
    this.floor = List<int>.of(floor);
    this.stock = List<int>.of(stock);
    captured[0].addAll(captured0);
    captured[1].addAll(captured1);
  }

  final Random _rng;
  final int firstPlayer;
  final List<List<int>> hands = [[], []];
  final List<List<int>> captured = [[], []];
  List<int> floor = [];
  List<int> stock = [];
  int turn = 0;
  Phase phase = Phase.playCard;
  final List<int> goCount = [0, 0];
  final List<int> lastGoScore = [
    MatgoConfig.minScoreToStop - 1,
    MatgoConfig.minScoreToStop - 1,
  ];
  TurnCtx ctx = TurnCtx();
  List<GameEvent> events = [];
  int? lastHand;
  int? lastStock;
  int? lastBy;
  GameResult? result;

  // ------------------------------------------------------------ 분배

  void _deal() {
    final hs = MatgoConfig.handSize;
    final fs = MatgoConfig.floorSize;
    while (true) {
      final deck = List<int>.generate(48, (i) => i)..shuffle(_rng);
      final h0 = deck.sublist(0, hs);
      final h1 = deck.sublist(hs, hs * 2);
      final fl = deck.sublist(hs * 2, hs * 2 + fs);
      final st = deck.sublist(hs * 2 + fs);
      // 같은 월 4장이 한 곳에 몰리면(총통 포함) 다시 섞는다
      if (_hasFour(h0) || _hasFour(h1) || _hasFour(fl)) continue;
      hands[0]
        ..clear()
        ..addAll(h0);
      hands[1]
        ..clear()
        ..addAll(h1);
      floor = fl;
      stock = st;
      return;
    }
  }

  bool _hasFour(List<int> ids) {
    final cnt = List<int>.filled(13, 0);
    for (final i in ids) {
      cnt[allCards[i].month]++;
    }
    return cnt.any((n) => n >= 4);
  }

  /// 다음 판의 선공. 이긴 사람이 먼저 한다.
  int nextFirst() =>
      (result != null && result!.winner >= 0) ? result!.winner : firstPlayer;

  // -------------------------------------------------------- 플레이어 행동

  bool playCard(int p, int cardId) {
    if (phase != Phase.playCard || turn != p || !hands[p].contains(cardId)) {
      return false;
    }
    events = [];
    hands[p].remove(cardId);
    ctx = TurnCtx()..hand = cardId;
    lastHand = cardId;
    lastStock = null;
    lastBy = p;

    final m = allCards[cardId].month;
    final matches = floor.where((c) => allCards[c].month == m).toList();
    if (matches.isEmpty) {
      ctx.hcase = HandCase.unmatched;
      floor.add(cardId);
      _flip(p);
    } else if (matches.length == 1) {
      ctx.hcase = HandCase.paired;
      ctx.partner = matches[0];
      _flip(p);
    } else if (matches.length == 2) {
      ctx.options = matches;
      phase = Phase.chooseFloorHand;
    } else {
      // 바닥에 같은 월 3장: 4장을 모두 먹는다
      ctx.hcase = HandCase.captured;
      floor.removeWhere(matches.contains);
      _capture(p, [cardId, ...matches]);
      _ev(p, 'eat3');
      _steal(p);
      _flip(p);
    }
    return true;
  }

  bool chooseFloor(int p, int cardId) {
    if (turn != p) return false;
    if (phase == Phase.chooseFloorHand) {
      if (!ctx.options.contains(cardId)) return false;
      ctx.hcase = HandCase.pairedFromTwo;
      ctx.partner = cardId;
      ctx.other = ctx.options.firstWhere((c) => c != cardId);
      ctx.options = [];
      phase = Phase.playCard;
      _flip(p);
      return true;
    }
    if (phase == Phase.chooseFloorStock) {
      if (!ctx.options.contains(cardId)) return false;
      floor.remove(cardId);
      _capture(p, [ctx.stockCard!, cardId]);
      ctx.options = [];
      _finishTurn(p);
      return true;
    }
    return false;
  }

  bool goStop(int p, bool go) {
    if (phase != Phase.goStop || turn != p) return false;
    events = [];
    if (go) {
      goCount[p]++;
      lastGoScore[p] = scoreOf(captured[p]).total;
      _ev(p, 'go');
      turn = 1 - p;
      phase = Phase.playCard;
    } else {
      _endStop(p);
    }
    return true;
  }

  // ------------------------------------------------------------ 내부 진행

  void _flip(int p) {
    if (stock.isEmpty) {
      _finishTurn(p);
      return;
    }
    final s = stock.removeLast();
    ctx.stockCard = s;
    lastStock = s;
    final h = ctx.hand!;
    final sameMonth = allCards[s].month == allCards[h].month;

    switch (ctx.hcase) {
      case HandCase.unmatched:
        if (sameMonth) {
          // 쪽: 방금 낸 패가 더미 패와 짝이 됨
          floor.remove(h);
          _capture(p, [h, s]);
          _ev(p, 'jjok');
          _steal(p);
          _finishTurn(p);
          return;
        }
        break;
      case HandCase.paired:
        if (sameMonth) {
          // 뻑: 같은 월 3장이 바닥에 남음
          floor.add(h);
          floor.add(s);
          ctx.partner = null;
          _ev(p, 'ppeok');
          _finishTurn(p);
          return;
        }
        break;
      case HandCase.pairedFromTwo:
        if (sameMonth) {
          // 따닥: 바닥 같은 월 2장과 내 패 더미 패 4장을 모두 먹음
          final x = ctx.partner!;
          final y = ctx.other!;
          floor.remove(x);
          floor.remove(y);
          _capture(p, [h, x, y, s]);
          ctx.partner = null;
          ctx.other = null;
          _ev(p, 'ttadak');
          _steal(p);
          _finishTurn(p);
          return;
        }
        break;
      case HandCase.captured:
      case HandCase.none:
        break;
    }
    _matchStock(p, s);
  }

  void _matchStock(int p, int s) {
    final m = allCards[s].month;
    final matches = floor.where((c) => allCards[c].month == m).toList();
    if (matches.isEmpty) {
      floor.add(s);
      _finishTurn(p);
    } else if (matches.length == 1) {
      floor.remove(matches[0]);
      _capture(p, [s, matches[0]]);
      _finishTurn(p);
    } else if (matches.length == 2) {
      ctx.options = matches;
      phase = Phase.chooseFloorStock;
    } else {
      floor.removeWhere(matches.contains);
      _capture(p, [s, ...matches]);
      _ev(p, 'eat3');
      _steal(p);
      _finishTurn(p);
    }
  }

  void _finishTurn(int p) {
    // 손패와 짝이 된 바닥패를 확정해서 먹는다
    if ((ctx.hcase == HandCase.paired ||
            ctx.hcase == HandCase.pairedFromTwo) &&
        ctx.partner != null) {
      floor.remove(ctx.partner);
      _capture(p, [ctx.hand!, ctx.partner!]);
    }
    if (floor.isEmpty) {
      _ev(p, 'sweep');
      _steal(p);
    }
    ctx = TurnCtx();

    final score = scoreOf(captured[p]).total;
    final bothEmpty = hands[0].isEmpty && hands[1].isEmpty;
    if (score >= MatgoConfig.minScoreToStop && score > lastGoScore[p]) {
      if (bothEmpty) {
        _endStop(p);
      } else {
        turn = p;
        phase = Phase.goStop;
      }
      return;
    }
    if (bothEmpty) {
      _endExhausted();
      return;
    }
    turn = 1 - p;
    phase = Phase.playCard;
  }

  void _capture(int p, List<int> ids) {
    captured[p].addAll(ids);
  }

  /// 상대가 먹은 피 중 값이 낮은 것부터 가져온다.
  void _steal(int p) {
    final opp = 1 - p;
    for (var n = 0; n < MatgoConfig.stealPiCount; n++) {
      final pis = captured[opp]
          .where((id) => allCards[id].kind == Kind.pi)
          .toList();
      if (pis.isEmpty) return;
      pis.sort((a, b) => allCards[a].piValue.compareTo(allCards[b].piValue));
      final take = pis.first;
      captured[opp].remove(take);
      captured[p].add(take);
      _ev(p, 'steal');
    }
  }

  void _ev(int p, String code) {
    events.add(GameEvent(p, code));
  }

  // ------------------------------------------------------------ 종료와 정산

  GameResult _calc(int w) {
    final l = 1 - w;
    final ws = scoreOf(captured[w]);
    final ls = scoreOf(captured[l]);
    final lines = <String>[];
    var pts = ws.total;
    lines.add('기본 ${ws.total}점');

    final g = goCount[w];
    if (g > 0) {
      final add = g >= 2 ? MatgoConfig.goAddSecond : MatgoConfig.goAddFirst;
      pts += add;
      lines.add('$g고 +$add');
    }
    if (g >= MatgoConfig.goMultiplierFrom) {
      final mult = 1 << (g - MatgoConfig.goMultiplierFrom + 1);
      pts *= mult;
      lines.add('고 배수 ×$mult');
    }
    if (ws.gwangScore > 0 && ls.gwangCount == 0) {
      pts *= MatgoConfig.gwangBakMultiplier;
      lines.add('광박 ×${MatgoConfig.gwangBakMultiplier}');
    }
    if (ws.piScore > 0 && ls.piValue <= MatgoConfig.piBakMaxPi) {
      pts *= MatgoConfig.piBakMultiplier;
      lines.add('피박 ×${MatgoConfig.piBakMultiplier}');
    }
    return GameResult(w, pts, lines, [
      scoreOf(captured[0]).lines,
      scoreOf(captured[1]).lines,
    ]);
  }

  void _endStop(int w) {
    result = _calc(w);
    phase = Phase.ended;
    _ev(w, 'stop');
  }

  /// 패가 모두 떨어진 경우: 고를 부른 사람이 있으면 그 사람이 이기고 없으면 나가리
  void _endExhausted() {
    final cand = [0, 1].where((i) => goCount[i] > 0).toList();
    GameResult? best;
    var tie = false;
    for (final i in cand) {
      final r = _calc(i);
      if (best == null || r.points > best.points) {
        best = r;
        tie = false;
      } else if (r.points == best.points) {
        tie = true;
      }
    }
    if (best == null || tie) {
      result = GameResult(-1, 0, ['나가리'], [
        scoreOf(captured[0]).lines,
        scoreOf(captured[1]).lines,
      ]);
      _ev(-1, 'nagari');
    } else {
      result = best;
      _ev(best.winner, 'stop');
    }
    phase = Phase.ended;
  }
}
