import 'dart:math';

import 'cards.dart';
import 'config.dart';
import 'scoring.dart';

/// flipStock: 손패를 낸 뒤 더미 패를 뒤집기를 기다리는 단계
enum Phase {
  playCard,
  chooseFloorHand,
  chooseFloorStock,
  flipStock,
  goStop,
  ended,
}

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
  final int points; // 이긴 사람이 받는 점수 합계 (진 사람들이 낸 점수의 합)
  final List<String> lines;
  final List<List<String>> details; // 플레이어별 족보 내역

  /// 플레이어별 점수 이동: 이긴 사람은 +, 진 사람은 -, 합은 0
  final List<int> payments;

  /// 진 사람별 박 내역 (광박 피박 고박 독박)
  final List<List<String>> bakLines;

  const GameResult(
    this.winner,
    this.points,
    this.lines,
    this.details, {
    this.payments = const [],
    this.bakLines = const [],
  });

  Map<String, dynamic> toJson() => {
        'winner': winner,
        'points': points,
        'lines': lines,
        'details': details,
        'payments': payments,
        'bakLines': bakLines,
      };

  factory GameResult.fromJson(Map<String, dynamic> j) => GameResult(
        j['winner'] as int,
        j['points'] as int,
        (j['lines'] as List).map((e) => e as String).toList(),
        (j['details'] as List)
            .map((d) => (d as List).map((e) => e as String).toList())
            .toList(),
        payments: ((j['payments'] as List?) ?? const [])
            .map((e) => e as int)
            .toList(),
        bakLines: ((j['bakLines'] as List?) ?? const [])
            .map((d) => (d as List).map((e) => e as String).toList())
            .toList(),
      );
}

/// 2인 또는 3인 맞고 규칙 엔진. UI와 통신을 모르는 순수 Dart 클래스다.
/// 방장 폰에서만 만들어서 쓴다.
class MatgoGame {
  MatgoGame({int players = 2, int first = 0, Random? rng})
      : n = players,
        _rng = rng ?? Random(),
        firstPlayer = first,
        hands = List.generate(players, (_) => <int>[]),
        captured = List.generate(players, (_) => <int>[]),
        goCount = List<int>.filled(players, 0),
        lastGoScore =
            List<int>.filled(players, MatgoConfig.minScoreToStop - 1),
        shakeCount = List<int>.filled(players, 0),
        _dummySeq = List<int>.filled(players, 0) {
    turn = first;
    _deal();
  }

  /// 테스트용 2인. stock의 마지막 원소가 더미의 맨 위다.
  MatgoGame.custom({
    required List<int> hand0,
    required List<int> hand1,
    required List<int> floor,
    required List<int> stock,
    List<int> captured0 = const [],
    List<int> captured1 = const [],
    int first = 0,
    Random? rng,
  }) : this.customN(
          hands: [hand0, hand1],
          floor: floor,
          stock: stock,
          captured: [captured0, captured1],
          first: first,
          rng: rng,
        );

  /// 테스트용 N인
  MatgoGame.customN({
    required List<List<int>> hands,
    required List<int> floor,
    required List<int> stock,
    List<List<int>>? captured,
    int first = 0,
    Random? rng,
  })  : n = hands.length,
        _rng = rng ?? Random(),
        firstPlayer = first,
        hands = List.generate(hands.length, (i) => List<int>.of(hands[i])),
        captured = List.generate(
          hands.length,
          (i) => captured == null ? <int>[] : List<int>.of(captured[i]),
        ),
        goCount = List<int>.filled(hands.length, 0),
        lastGoScore =
            List<int>.filled(hands.length, MatgoConfig.minScoreToStop - 1),
        shakeCount = List<int>.filled(hands.length, 0),
        _dummySeq = List<int>.filled(hands.length, 0) {
    turn = first;
    this.floor = List<int>.of(floor);
    this.stock = List<int>.of(stock);
  }

  final int n; // 플레이어 수
  final Random _rng;
  final int firstPlayer;
  final List<List<int>> hands;
  final List<List<int>> captured;
  List<int> floor = [];
  List<int> stock = [];
  int turn = 0;
  Phase phase = Phase.playCard;
  final List<int> goCount;
  final List<int> lastGoScore;
  TurnCtx ctx = TurnCtx();
  List<GameEvent> events = [];
  List<int> lastHands = []; // 이번 턴에 낸 손패 (폭탄이면 3장)
  int? lastStock;
  int? lastBy;
  GameResult? result;

  /// 폭탄 또는 흔들기를 선언한 횟수. 이긴 사람의 점수에 2배씩 곱한다.
  final List<int> shakeCount;
  final List<int> _dummySeq;

  // ------------------------------------------------------------ 분배

  void _deal() {
    final hs = MatgoConfig.handSizeFor(n);
    final fs = MatgoConfig.floorSizeFor(n);
    while (true) {
      final deck = List<int>.generate(48, (i) => i)..shuffle(_rng);
      final hh = [for (var i = 0; i < n; i++) deck.sublist(i * hs, (i + 1) * hs)];
      final fl = deck.sublist(n * hs, n * hs + fs);
      final st = deck.sublist(n * hs + fs);
      // 같은 월 4장이 한 곳에 몰리면(총통 포함) 다시 섞는다
      if (hh.any(_hasFour) || _hasFour(fl)) continue;
      for (var i = 0; i < n; i++) {
        hands[i]
          ..clear()
          ..addAll(hh[i]);
      }
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

  /// shake가 true이고 손에 같은 월 3장 + 바닥에 같은 월 0장이면 흔들기로 처리한다.
  bool playCard(int p, int cardId, {bool shake = false}) {
    if (phase != Phase.playCard || turn != p || !hands[p].contains(cardId)) {
      return false;
    }
    events = [];
    lastHands = [cardId];
    lastStock = null;
    lastBy = p;
    ctx = TurnCtx()..hand = cardId;

    // 폭탄패(빈 패)는 바닥과 상관없이 더미만 뒤집는다
    if (isDummyId(cardId)) {
      hands[p].remove(cardId);
      ctx.hcase = HandCase.none;
      _afterHand(p);
      return true;
    }

    final m = allCards[cardId].month;
    final inHand = hands[p]
        .where((c) => !isDummyId(c) && allCards[c].month == m)
        .length;
    final matches = floor.where((c) => allCards[c].month == m).toList();
    if (shake && inHand >= 3 && matches.isEmpty) {
      shakeCount[p]++;
      _ev(p, 'shake');
    }

    hands[p].remove(cardId);
    if (matches.isEmpty) {
      ctx.hcase = HandCase.unmatched;
      floor.add(cardId);
      _afterHand(p);
    } else if (matches.length == 1) {
      ctx.hcase = HandCase.paired;
      ctx.partner = matches[0];
      _afterHand(p);
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
      _afterHand(p);
    }
    return true;
  }

  /// 폭탄: 손에 같은 월 3장 + 바닥에 같은 월 1장이면 3장을 한꺼번에 내서 4장을 먹는다.
  /// 상대 피 1장을 가져오고 폭탄패 2장을 받는다(남은 턴 수를 맞추기 위해서).
  bool playBomb(int p, int month) {
    if (phase != Phase.playCard || turn != p) return false;
    final mine = hands[p]
        .where((c) => !isDummyId(c) && allCards[c].month == month)
        .toList();
    final fl = floor.where((c) => allCards[c].month == month).toList();
    if (mine.length != 3 || fl.length != 1) return false;

    events = [];
    ctx = TurnCtx()
      ..hand = mine.first
      ..hcase = HandCase.captured;
    lastHands = List<int>.of(mine);
    lastStock = null;
    lastBy = p;
    for (final c in mine) {
      hands[p].remove(c);
    }
    floor.remove(fl.first);
    _capture(p, [...mine, fl.first]);
    shakeCount[p]++;
    _ev(p, 'bomb');
    _steal(p);
    for (var k = 0; k < 2; k++) {
      hands[p].add(kDummyBase + p * 10 + _dummySeq[p]);
      _dummySeq[p]++;
    }
    _afterHand(p);
    return true;
  }

  /// 손패 처리가 끝나면 더미 패를 뒤집을 차례를 기다린다. 더미가 없으면 바로 턴을 끝낸다.
  void _afterHand(int p) {
    if (stock.isEmpty) {
      _finishTurn(p);
    } else {
      phase = Phase.flipStock;
    }
  }

  /// 더미 맨 위 패를 뒤집는다. UI가 플레이어의 터치를 받았을 때 호출한다.
  bool flipStock(int p) {
    if (phase != Phase.flipStock || turn != p) return false;
    events = [];
    phase = Phase.playCard; // 아래 처리에서 필요하면 바뀐다
    _flip(p);
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
      _afterHand(p);
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
      turn = (p + 1) % n;
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
    final sameMonth = !isDummyId(h) && allCards[s].month == allCards[h].month;

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
    final bothEmpty = hands.every((h) => h.isEmpty);
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
    turn = (p + 1) % n;
    phase = Phase.playCard;
  }

  void _capture(int p, List<int> ids) {
    captured[p].addAll(ids);
  }

  /// 다른 모든 플레이어에게서 값이 낮은 피부터 가져온다.
  void _steal(int p) {
    for (var o = 0; o < n; o++) {
      if (o == p) continue;
      for (var k = 0; k < MatgoConfig.stealPiCount; k++) {
        final pis = captured[o]
            .where((id) => allCards[id].kind == Kind.pi)
            .toList();
        if (pis.isEmpty) break;
        pis.sort((a, b) => allCards[a].piValue.compareTo(allCards[b].piValue));
        final take = pis.first;
        captured[o].remove(take);
        captured[p].add(take);
        _ev(p, 'steal');
      }
    }
  }

  void _ev(int p, String code) {
    events.add(GameEvent(p, code));
  }

  // ------------------------------------------------------------ 종료와 정산

  GameResult _calc(int w) {
    final ws = scoreOf(captured[w]);
    final lines = <String>[];
    var base = ws.total;
    lines.add('기본 ${ws.total}점');

    final g = goCount[w];
    if (g > 0) {
      final add = g >= 2 ? MatgoConfig.goAddSecond : MatgoConfig.goAddFirst;
      base += add;
      lines.add('$g고 +$add');
    }
    if (g >= MatgoConfig.goMultiplierFrom) {
      final mult = 1 << (g - MatgoConfig.goMultiplierFrom + 1);
      base *= mult;
      lines.add('고 배수 ×$mult');
    }

    final sh = shakeCount[w];
    final shMult = sh > 0 ? 1 << sh : 1;

    // 진 사람마다 박을 따로 계산한다
    final losers = [for (var i = 0; i < n; i++) if (i != w) i];
    final share = List<int>.filled(n, 0);
    final bak = List.generate(n, (_) => <String>[]);
    for (final l in losers) {
      final ls = scoreOf(captured[l]);
      var pts = base;
      if (ws.gwangScore > 0 && ls.gwangCount == 0) {
        pts *= MatgoConfig.gwangBakMultiplier;
        bak[l].add('광박 ×${MatgoConfig.gwangBakMultiplier}');
      }
      if (ws.piScore > 0 && ls.piValue <= MatgoConfig.piBakMaxPi) {
        pts *= MatgoConfig.piBakMultiplier;
        bak[l].add('피박 ×${MatgoConfig.piBakMultiplier}');
      }
      if (n == 2 && goCount[l] > 0) {
        // 2인 고박: 고를 불렀다가 상대에게 먼저 난 경우
        pts *= MatgoConfig.goBakMultiplier;
        bak[l].add('고박 ×${MatgoConfig.goBakMultiplier}');
      }
      pts *= shMult;
      share[l] = pts;
    }

    final pay = List<int>.filled(n, 0);
    final callers = losers.where((l) => goCount[l] > 0).toList();
    if (n >= 3 && callers.length == 1) {
      // 3인 고박(독박): 고를 부른 사람이 다른 진 사람 몫까지 혼자 낸다
      final c = callers.first;
      final others = losers.where((l) => l != c).toList();
      final extra = others.fold(0, (a, o) => a + share[o]);
      pay[c] = -(share[c] + extra);
      bak[c].add('독박 (다른 사람 몫 $extra점 포함)');
    } else {
      for (final l in losers) {
        pay[l] = -share[l];
      }
    }
    final total = -pay.fold(0, (a, b) => a + b);
    pay[w] = total;

    // 2인은 예전 표시를 그대로 쓴다 (박 줄이 점수 줄에 섞여 들어간다)
    if (n == 2) {
      lines.addAll(bak[losers.first]);
    }
    if (shMult > 1) {
      lines.add('폭탄/흔들기 ×$shMult');
    }
    return GameResult(
      w,
      total,
      lines,
      [for (var i = 0; i < n; i++) scoreOf(captured[i]).lines],
      payments: pay,
      bakLines: bak,
    );
  }

  void _endStop(int w) {
    result = _calc(w);
    phase = Phase.ended;
    _ev(w, 'stop');
  }

  /// 패가 모두 떨어진 경우: 고를 부른 사람이 있으면 그 사람이 이기고 없으면 나가리
  void _endExhausted() {
    final cand = [for (var i = 0; i < n; i++) if (goCount[i] > 0) i];
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
      result = GameResult(
        -1,
        0,
        ['나가리'],
        [for (var i = 0; i < n; i++) scoreOf(captured[i]).lines],
        payments: List<int>.filled(n, 0),
        bakLines: List.generate(n, (_) => <String>[]),
      );
      _ev(-1, 'nagari');
    } else {
      result = best;
      _ev(best.winner, 'stop');
    }
    phase = Phase.ended;
  }
}
