import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/cards.dart';
import '../game/matgo_game.dart';
import '../game/session.dart';
import '../game/view_state.dart';
import '../game/wallet.dart';
import '../net/nearby_transport.dart';
import '../net/transport.dart';
import 'card_sprite.dart';
import 'table_layout.dart';
import 'wallet_panel.dart';

String eventText(GameEvent e, int me) {
  final who = e.p == me ? '나' : '상대';
  switch (e.code) {
    case 'ppeok':
      return '$who: 뻑!';
    case 'ttadak':
      return '$who: 따닥!';
    case 'jjok':
      return '$who: 쪽!';
    case 'sweep':
      return '$who: 싹쓸이!';
    case 'eat3':
      return '$who: 3장 먹기!';
    case 'steal':
      return '$who: 피 1장 가져옴';
    case 'go':
      return '$who: 고!';
    case 'stop':
      return '$who: 스톱!';
    case 'shake':
      return '$who: 흔들기! (점수 ×2)';
    case 'bomb':
      return '$who: 폭탄! (점수 ×2)';
    case 'nagari':
      return '나가리';
  }
  return e.code;
}

const Set<String> _strongEvents = {
  'jjok',
  'ppeok',
  'ttadak',
  'sweep',
  'eat3',
  'bomb',
  'shake',
  'go',
  'stop',
};

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.session, required this.t});

  final MatgoSession session;
  final GameTransport t;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  int? selHand;
  int? selFloor;
  LinkState link = LinkState.connected;
  DateTime? reconnectSince;
  Timer? tick;
  StreamSubscription<LinkState>? linkSub;

  // 이전 상태와 비교해서 어떤 카드가 새로 나타났는지 알아내기 위한 값
  ViewState? _prev;
  final Map<int, int> _slotOf = {}; // 바닥 카드 id -> 바닥 칸 번호
  final Map<int, Offset> _spawn = {};
  final Map<int, double> _spawnW = {};
  final Set<int> _spawnFaceDown = {};
  int _stepDelay = 0;
  DateTime _stepUntil = DateTime.fromMillisecondsSinceEpoch(0);

  String? _banner;
  int _bannerSeq = 0;
  final List<Timer> _timers = [];
  bool _showResult = false;
  bool _resultTimerSet = false;

  MatgoSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    link = widget.t.current;
    final v = s.view;
    if (v != null) {
      _syncSlots(v);
      _prev = v;
    }
    s.addListener(_onView);
    linkSub = widget.t.state.listen(_onLink);
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && link == LinkState.reconnecting) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    linkSub?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    s.removeListener(_onView);
    super.dispose();
  }

  // ------------------------------------------------------------- 상태 변화

  void _syncSlots(ViewState v) {
    _slotOf.removeWhere((id, _) => !v.floor.contains(id));
    final used = _slotOf.values.toSet();
    for (final id in v.floor) {
      if (_slotOf.containsKey(id)) continue;
      var k = 0;
      while (used.contains(k)) {
        k++;
      }
      _slotOf[id] = k;
      used.add(k);
    }
  }

  Set<int> _cardIds(ViewState v) => {
        ...v.hand,
        ...v.floor,
        ...v.captured[0],
        ...v.captured[1],
        ...v.lastHands,
        if (v.lastStock != null) v.lastStock!,
      };

  bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onView() {
    if (!mounted) return;
    final v = s.view;
    if (v == null) return;
    final prev = _prev;
    _spawn.clear();
    _spawnW.clear();
    _spawnFaceDown.clear();
    _stepDelay = 0;
    _syncSlots(v);
    if (prev != null && prev.seq != v.seq) {
      _planStep(prev, v);
    }
    _prev = v;

    if (v.phase == Phase.ended) {
      if (!_resultTimerSet) {
        _resultTimerSet = true;
        _later(2200, () {
          if (s.view?.phase == Phase.ended) {
            setState(() => _showResult = true);
          }
        });
      }
    } else {
      _resultTimerSet = false;
      _showResult = false;
    }

    setState(() {
      selHand = null;
      selFloor = null;
    });
  }

  void _later(int ms, VoidCallback f) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) f();
    }));
  }

  /// 새 상태가 들어왔을 때 어떤 움직임을 보여 줄지 정한다.
  void _planStep(ViewState prev, ViewState v) {
    final known = _cardIds(prev);
    final now = _cardIds(v);
    final flipStep = prev.phase == Phase.flipStock &&
        v.phase != Phase.flipStock &&
        v.lastStock != null;
    final handStep =
        v.lastHands.isNotEmpty && !_sameList(v.lastHands, prev.lastHands);

    _stepDelay = flipStep ? 850 : 0;
    _stepUntil = DateTime.now().add(const Duration(milliseconds: 1800));

    for (final id in now) {
      if (known.contains(id)) continue;
      if (flipStep && id == v.lastStock) {
        _spawn[id] = TableLayout.deck;
        _spawnW[id] = TableLayout.floorW;
        _spawnFaceDown.add(id);
      } else if (v.lastHands.contains(id) && v.lastBy != v.me) {
        final k = v.lastHands.indexOf(id);
        final base = TableLayout.oppBackPos(
          v.oppHandCount,
          v.oppHandCount + 1,
        );
        _spawn[id] = Offset(base.dx + k * 14, base.dy);
        _spawnW[id] = TableLayout.oppW;
      }
    }
    _scheduleFx(v, flipStep, handStep);
  }

  /// 진동과 문구를 카드가 도착하는 시점에 맞춘다.
  void _scheduleFx(ViewState v, bool flipStep, bool handStep) {
    final land = flipStep ? 850 + 520 : 520;
    if (flipStep) {
      _later(320, () => HapticFeedback.selectionClick());
    }
    final strong = v.events.any((e) => _strongEvents.contains(e.code));
    if (strong) {
      _later(land, () => HapticFeedback.heavyImpact());
    } else if (flipStep || handStep) {
      _later(land, () => HapticFeedback.lightImpact());
    }

    final texts = v.events.map((e) => eventText(e, v.me)).toList();
    if (texts.isNotEmpty) {
      final text = texts.join('   ');
      final token = ++_bannerSeq;
      final showAt = flipStep ? 900 : 250;
      _later(showAt, () => setState(() => _banner = text));
      _later(showAt + 2300, () {
        if (_bannerSeq == token) setState(() => _banner = null);
      });
    }
  }

  void _onLink(LinkState st) {
    if (!mounted) return;
    setState(() {
      if (st == LinkState.reconnecting && link != LinkState.reconnecting) {
        reconnectSince = DateTime.now();
      }
      link = st;
    });
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게임을 나갈까?'),
        content: const Text('나가면 연결이 끊기고 진행 중인 판은 사라져.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = s.view;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1B5E20),
        body: SafeArea(
          child: Stack(
            children: [
              if (s.versionMismatch)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '두 폰의 앱 버전이 달라.\n두 폰 모두 옛날 앱을 지우고\n최신 APK를 다시 설치해줘.\n(로비 맨 아래 버전이 같아야 해)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                    ),
                  ),
                )
              else if (v == null)
                const Center(
                  child: Text(
                    '게임 정보를 기다리는 중...',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              else
                Center(child: _table(v)),
              if (v != null && v.phase == Phase.ended && _showResult)
                _resultOverlay(v),
              if (link == LinkState.reconnecting) _reconnectOverlay(),
              if (link == LinkState.failed) _failedOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- 게임판

  void _tapHand(int id) {
    setState(() => selHand = selHand == id ? null : id);
  }

  void _tapFloor(int id) {
    setState(() => selFloor = id);
  }

  Offset _pendingPos(int id, ViewState v) {
    if (isDummyId(id)) return TableLayout.playSpot;
    final m = allCards[id].month;
    for (final f in v.floor) {
      if (allCards[f].month == m) {
        final slot = _slotOf[f];
        if (slot != null) {
          final b = TableLayout.floorSlot(slot);
          return Offset(b.dx + 14, b.dy + 16);
        }
      }
    }
    return TableLayout.playSpot;
  }

  Widget _table(ViewState v) {
    final specs = _buildSpecs(v);
    specs.sort((a, b) => a.z.compareTo(b.z));
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: TableLayout.width,
        height: TableLayout.height,
        child: Stack(
          children: [
            ..._boardBackgrounds(),
            for (final sp in specs)
              CardSprite(key: ValueKey(sp.key), spec: sp),
            ..._overlays(v),
          ],
        ),
      ),
    );
  }

  List<SpriteSpec> _buildSpecs(ViewState v) {
    final specs = <SpriteSpec>[];
    final myTurn = v.turn == v.me;
    final canPlay = myTurn && v.phase == Phase.playCard;
    final canFlip = myTurn && v.phase == Phase.flipStock;
    final pickingFloor = myTurn &&
        (v.phase == Phase.chooseFloorHand || v.phase == Phase.chooseFloorStock);
    final selMonth = (selHand == null || isDummyId(selHand!))
        ? null
        : allCards[selHand!].month;
    final shown = <int>{};

    // 더미
    specs.add(SpriteSpec(
      key: 'deck',
      id: null,
      pos: TableLayout.deck,
      w: TableLayout.floorW,
      z: 0,
      highlight: canFlip,
      onTap: canFlip ? () => s.flip() : null,
    ));

    // 상대 손패 (뒷면)
    for (var i = 0; i < v.oppHandCount; i++) {
      specs.add(SpriteSpec(
        key: 'ob$i',
        id: null,
        pos: TableLayout.oppBackPos(i, v.oppHandCount),
        w: TableLayout.oppW,
        z: 100 + i,
      ));
    }

    // 먹은 패: 왼쪽이 상대 오른쪽이 나
    var k = 0;
    for (var side = 0; side < 2; side++) {
      final owner = side == 0 ? 1 - v.me : v.me;
      final origin = side == 0 ? TableLayout.oppBoard : TableLayout.myBoard;
      final pos = TableLayout.captured(v.captured[owner], origin);
      pos.forEach((id, p) {
        specs.add(SpriteSpec(
          key: 'c$id',
          id: id,
          pos: p,
          w: TableLayout.capW,
          z: 2000 + k,
        ));
        shown.add(id);
        k++;
      });
    }

    // 바닥
    for (final id in v.floor) {
      final slot = _slotOf[id] ?? 0;
      final opt = pickingFloor && v.options.contains(id);
      specs.add(SpriteSpec(
        key: 'c$id',
        id: id,
        pos: TableLayout.floorSlot(slot),
        w: TableLayout.floorW,
        z: 3000 + slot,
        selected: pickingFloor && selFloor == id,
        highlight: pickingFloor
            ? opt
            : (selMonth != null && allCards[id].month == selMonth),
        dim: pickingFloor && !opt,
        onTap: opt ? () => _tapFloor(id) : null,
      ));
      shown.add(id);
    }

    // 내 손패
    final n = v.hand.length;
    for (var i = 0; i < n; i++) {
      final id = v.hand[i];
      final sel = selHand == id;
      final p = TableLayout.handPos(i, n);
      specs.add(SpriteSpec(
        key: 'c$id',
        id: id,
        pos: Offset(p.dx, p.dy + (sel ? -12 : 0)),
        w: TableLayout.handW,
        z: 4000 + i,
        selected: sel,
        dim: !canPlay,
        fast: true,
        onTap: canPlay ? () => _tapHand(id) : null,
      ));
      shown.add(id);
    }

    // 방금 낸 패 / 뒤집은 패 (아직 바닥이나 먹은 패로 정리되지 않은 것)
    final pend = <int>[
      ...v.lastHands,
      if (v.lastStock != null) v.lastStock!,
    ];
    var pk = 0;
    for (final id in pend) {
      if (shown.contains(id)) continue;
      specs.add(SpriteSpec(
        key: 'c$id',
        id: id,
        pos: _pendingPos(id, v),
        w: TableLayout.floorW,
        z: 5000 + pk,
      ));
      shown.add(id);
      pk++;
    }

    final delay = DateTime.now().isBefore(_stepUntil) ? _stepDelay : 0;
    for (final sp in specs) {
      final id = sp.id;
      if (id != null) {
        sp.spawn = _spawn[id];
        sp.spawnW = _spawnW[id];
        sp.spawnFaceDown = _spawnFaceDown.contains(id);
      }
      sp.delayMs = delay;
    }
    return specs;
  }

  Color _slotColor(String kind) {
    switch (kind) {
      case 'gwang':
        return const Color(0x44FFC107);
      case 'yeol':
        return const Color(0x44FF9800);
      case 'hong':
        return const Color(0x44F44336);
      case 'cheong':
        return const Color(0x442196F3);
      case 'cho':
        return const Color(0x5581C784);
      case 'tti':
        return const Color(0x33FFFFFF);
      default:
        return const Color(0x22FFFFFF);
    }
  }

  List<Widget> _boardBackgrounds() {
    final out = <Widget>[];
    for (final o in [TableLayout.oppBoard, TableLayout.myBoard]) {
      for (final sl in TableLayout.slots(o)) {
        out.add(Positioned(
          left: sl.left,
          top: sl.top,
          width: sl.width,
          height: sl.height,
          child: Container(
            alignment:
                sl.kind == 'pi' ? Alignment.topRight : Alignment.centerRight,
            padding: const EdgeInsets.only(right: 3, top: 2),
            decoration: BoxDecoration(
              color: _slotColor(sl.kind),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sl.label,
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
          ),
        ));
      }
    }
    return out;
  }

  String _head(ViewState v, int owner, String label) {
    final turnMark = (v.turn == owner && v.phase != Phase.ended) ? '▶ ' : '';
    var t = '$turnMark$label ${v.scores[owner]}점';
    if (v.goCount[owner] > 0) t += ' · ${v.goCount[owner]}고';
    if (v.shakes[owner] > 0) t += ' · ×${1 << v.shakes[owner]}';
    return t;
  }

  Widget _label(double left, String text, bool bold) {
    return Positioned(
      left: left,
      top: 6,
      width: 198,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: bold ? Colors.white : Colors.white70,
          fontSize: 14,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  List<Widget> _overlays(ViewState v) {
    final myTurn = v.turn == v.me;
    final canPlay = myTurn && v.phase == Phase.playCard;
    final canFlip = myTurn && v.phase == Phase.flipStock;

    // 폭탄과 흔들기 가능 여부
    int? selMonth;
    var inHandSame = 0;
    var floorSame = 0;
    if (selHand != null && !isDummyId(selHand!)) {
      selMonth = allCards[selHand!].month;
      inHandSame = v.hand
          .where((c) => !isDummyId(c) && allCards[c].month == selMonth)
          .length;
      floorSame = v.floor.where((c) => allCards[c].month == selMonth).length;
    }
    final canBomb = canPlay && inHandSame == 3 && floorSame == 1;
    final canShake = canPlay && inHandSame >= 3 && floorSame == 0;

    String prompt;
    if (v.phase == Phase.ended) {
      prompt = '판이 끝났어';
    } else if (!myTurn) {
      prompt = v.phase == Phase.goStop
          ? '상대가 고/스톱을 고르는 중'
          : (v.phase == Phase.flipStock ? '상대가 더미를 뒤집는 중' : '상대 차례');
    } else if (v.phase == Phase.playCard) {
      if (canBomb) {
        prompt = '폭탄 가능! 바닥에 같은 월이 1장 있어';
      } else if (canShake) {
        prompt = '같은 월 3장이 있어. 흔들면 점수 ×2';
      } else {
        prompt = '내 차례: 낼 패를 골라줘';
      }
    } else if (v.phase == Phase.flipStock) {
      prompt = '더미를 눌러서 패를 뒤집어줘';
    } else if (v.phase == Phase.goStop) {
      prompt = '고 / 스톱을 선택해줘';
    } else {
      prompt = '먹을 바닥패를 골라줘';
    }

    const gap = SizedBox(width: 8);
    final buttons = <Widget>[];
    if (canPlay) {
      buttons.add(FilledButton(
        onPressed: selHand != null ? () => s.play(selHand!) : null,
        child: const Text('확정 (패 내기)'),
      ));
      if (canBomb) {
        buttons.add(gap);
        buttons.add(FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => s.bomb(selMonth!),
          child: const Text('폭탄! (3장)'),
        ));
      }
      if (canShake) {
        buttons.add(gap);
        buttons.add(FilledButton.tonal(
          onPressed: () => s.play(selHand!, shake: true),
          child: const Text('흔들고 내기 (×2)'),
        ));
      }
    } else if (myTurn &&
        (v.phase == Phase.chooseFloorHand ||
            v.phase == Phase.chooseFloorStock)) {
      buttons.add(FilledButton(
        onPressed: selFloor != null ? () => s.choose(selFloor!) : null,
        child: const Text('확정 (바닥패 선택)'),
      ));
    } else if (myTurn && v.phase == Phase.goStop) {
      buttons.add(FilledButton(
        onPressed: () => s.goStop(true),
        child: const Text('고'),
      ));
      buttons.add(gap);
      buttons.add(FilledButton.tonal(
        onPressed: () => s.goStop(false),
        child: const Text('스톱'),
      ));
    }

    return [
      _label(TableLayout.oppBoard.dx, _head(v, 1 - v.me, '상대'),
          v.turn != v.me),
      _label(TableLayout.myBoard.dx, _head(v, v.me, '나'), v.turn == v.me),
      // 내 돈 (누르면 지갑)
      Positioned(
        left: 6,
        top: 346,
        width: 140,
        child: ListenableBuilder(
          listenable: Wallet.i,
          builder: (context, _) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showWallet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    won(Wallet.i.money),
                    style: TextStyle(
                      color: Wallet.i.money < 0
                          ? Colors.redAccent
                          : Colors.yellowAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    Wallet.i.debt > 0 ? '빚 ${won(Wallet.i.debt)}' : '지갑 열기',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // 남은 더미 장수
      Positioned(
        left: TableLayout.deck.dx,
        top: TableLayout.deck.dy + 24,
        width: TableLayout.floorW,
        child: IgnorePointer(
          child: Text(
            '${v.stockCount}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ),
      if (canFlip)
        Positioned(
          left: TableLayout.deck.dx - 8,
          top: TableLayout.deck.dy + TableLayout.h(TableLayout.floorW) + 4,
          width: TableLayout.floorW + 16,
          child: const IgnorePointer(
            child: Text(
              '눌러서\n뒤집기',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.yellowAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      Positioned(
        left: 215,
        top: 250,
        width: 470,
        child: IgnorePointer(
          child: Text(
            prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.yellowAccent, fontSize: 14),
          ),
        ),
      ),
      Positioned(
        left: 215,
        top: 272,
        width: 470,
        height: 36,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: buttons,
        ),
      ),
      if (_banner != null)
        Positioned(
          left: 215,
          top: 222,
          width: 470,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _banner!,
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  // ------------------------------------------------------------ 오버레이

  Widget _resultOverlay(ViewState v) {
    final r = v.result!;
    final title = r.winner < 0 ? '나가리' : (r.winner == v.me ? '승리!' : '패배');
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (r.winner >= 0)
                  Text('${r.points}점', style: const TextStyle(fontSize: 22)),
                ListenableBuilder(
                  listenable: Wallet.i,
                  builder: (context, _) {
                    final w = Wallet.i;
                    final d = w.lastDeltaGameId == v.gameId ? w.lastDelta : 0;
                    final sign = d > 0 ? '+' : '';
                    return Text(
                      r.winner < 0
                          ? '돈 이동 없음 · 잔액 ${won(w.money)}'
                          : '$sign${won(d)} · 잔액 ${won(w.money)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: d < 0 ? Colors.red : Colors.green.shade700,
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () => showWallet(context),
                  child: const Text('지갑 (대출)'),
                ),
                const SizedBox(height: 6),
                for (final l in r.lines) Text(l),
                const Divider(),
                Text('내 족보: ${_joinOrNone(r.details[v.me])}'),
                Text('상대 족보: ${_joinOrNone(r.details[1 - v.me])}'),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: s.newGame,
                  child: const Text('다시 하기'),
                ),
                if (!s.isHost)
                  const Text(
                    '방장에게 새 판을 요청해',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _joinOrNone(List<String> l) => l.isEmpty ? '없음' : l.join(' / ');

  Widget _reconnectOverlay() {
    final since = reconnectSince ?? DateTime.now();
    final left = (kReconnectWindow.inSeconds -
            DateTime.now().difference(since).inSeconds)
        .clamp(0, kReconnectWindow.inSeconds);
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          const Text(
            '연결이 끊겼어. 다시 연결하는 중...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          Text(
            '남은 시간 $left초',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          const Text(
            '두 폰을 가까이 두고 블루투스와 위치를 켜둬',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _failedOverlay() {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '연결이 끊겼어',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('처음으로'),
          ),
        ],
      ),
    );
  }
}
