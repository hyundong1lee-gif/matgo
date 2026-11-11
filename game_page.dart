import 'dart:async';

import 'package:flutter/material.dart';

import '../game/cards.dart';
import '../game/matgo_game.dart';
import '../game/session.dart';
import '../game/view_state.dart';
import '../net/nearby_transport.dart';
import '../net/transport.dart';
import 'card_widgets.dart';

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
    case 'nagari':
      return '나가리';
  }
  return e.code;
}

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

  MatgoSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    link = widget.t.current;
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
    s.removeListener(_onView);
    super.dispose();
  }

  void _onView() {
    if (!mounted) return;
    setState(() {
      selHand = null;
      selFloor = null;
    });
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
              if (v == null)
                const Center(
                  child: Text(
                    '게임 정보를 기다리는 중...',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              else
                _table(v),
              if (v != null && v.phase == Phase.ended) _resultOverlay(v),
              if (link == LinkState.reconnecting) _reconnectOverlay(),
              if (link == LinkState.failed) _failedOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- 게임판

  Widget _table(ViewState v) {
    return LayoutBuilder(builder: (context, c) {
      final scale = (c.maxHeight / 330).clamp(0.7, 1.4).toDouble();
      const side = 190.0;
      final mainW = c.maxWidth - side;
      final handW =
          ((mainW - 24) / 10 - 4).clamp(28.0, 50.0 * scale).toDouble();
      return Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _opponentRow(v, 22 * scale),
                Expanded(child: _center(v, 38 * scale)),
                _myCaptured(v, 22 * scale),
                _hand(v, handW),
              ],
            ),
          ),
          SizedBox(width: side, child: _sidePanel(v)),
        ],
      );
    });
  }

  Widget _opponentRow(ViewState v, double w) {
    final n = v.oppHandCount;
    final step = w * 0.45;
    return Container(
      height: w * 1.55 + 10,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: n == 0 ? 0 : w + step * (n - 1),
            height: w * 1.55,
            child: Stack(
              children: [
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: step * i,
                    child: CardView(w: w, animate: false),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CapturedRow(ids: v.captured[1 - v.me], w: w),
            ),
          ),
        ],
      ),
    );
  }

  Widget _myCaptured(ViewState v, double w) {
    return Container(
      height: w * 1.55 + 8,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: CapturedRow(ids: v.captured[v.me], w: w),
      ),
    );
  }

  Widget _center(ViewState v, double fw) {
    final myTurn = v.turn == v.me;
    final pickingFloor = myTurn &&
        (v.phase == Phase.chooseFloorHand || v.phase == Phase.chooseFloorStock);
    final selMonth = selHand == null ? null : allCards[selHand!].month;

    return Row(
      children: [
        SizedBox(
          width: fw * 2.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CardView(w: fw, animate: false),
                  Text(
                    '${v.stockCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v.lastHand != null)
                    CardView(
                      key: ValueKey('lh${v.lastHand}'),
                      id: v.lastHand,
                      w: fw * 0.75,
                    ),
                  if (v.lastStock != null)
                    CardView(
                      key: ValueKey('ls${v.lastStock}'),
                      id: v.lastStock,
                      w: fw * 0.75,
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in v.floor)
                        CardView(
                          key: ValueKey('f$id'),
                          id: id,
                          w: fw,
                          selected: pickingFloor && selFloor == id,
                          highlight: pickingFloor
                              ? v.options.contains(id)
                              : (selMonth != null &&
                                  allCards[id].month == selMonth),
                          dim: pickingFloor && !v.options.contains(id),
                          onTap: pickingFloor && v.options.contains(id)
                              ? () => setState(() => selFloor = id)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(top: 4, left: 0, right: 0, child: _banner(v)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _banner(ViewState v) {
    final texts = v.events.map((e) => eventText(e, v.me)).toList();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: texts.isEmpty
          ? SizedBox.shrink(key: ValueKey('b${v.seq}'))
          : Center(
              key: ValueKey('b${v.seq}'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  texts.join('   '),
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _hand(ViewState v, double w) {
    final canPlay = v.turn == v.me && v.phase == Phase.playCard;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final id in v.hand)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: CardView(
                key: ValueKey('h$id'),
                id: id,
                w: w,
                selected: selHand == id,
                dim: !canPlay,
                animate: false,
                onTap: canPlay
                    ? () => setState(
                        () => selHand = selHand == id ? null : id)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 오른쪽 패널

  String _scoreText(String label, int score, int go) {
    final g = go > 0 ? ' / $go고' : '';
    return '$label $score점$g';
  }

  Widget _sidePanel(ViewState v) {
    final myTurn = v.turn == v.me;
    String prompt;
    if (v.phase == Phase.ended) {
      prompt = '판이 끝났어';
    } else if (!myTurn) {
      prompt = v.phase == Phase.goStop ? '상대가 고/스톱을 고르는 중' : '상대 차례';
    } else if (v.phase == Phase.playCard) {
      prompt = '내 차례: 낼 패를 골라줘';
    } else if (v.phase == Phase.goStop) {
      prompt = '고 / 스톱을 선택해줘';
    } else {
      prompt = '먹을 바닥패를 골라줘';
    }

    final buttons = <Widget>[];
    if (myTurn && v.phase == Phase.playCard) {
      buttons.add(FilledButton(
        onPressed: selHand != null ? () => s.play(selHand!) : null,
        child: const Text('확정 (패 내기)'),
      ));
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
      buttons.add(const SizedBox(height: 6));
      buttons.add(FilledButton.tonal(
        onPressed: () => s.goStop(false),
        child: const Text('스톱'),
      ));
    }

    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _scoreText('상대', v.scores[1 - v.me], v.goCount[1 - v.me]),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            _scoreText('나', v.scores[v.me], v.goCount[v.me]),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Divider(color: Colors.white24),
          Text(prompt, style: const TextStyle(color: Colors.yellowAccent)),
          const Spacer(),
          ...buttons,
        ],
      ),
    );
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
