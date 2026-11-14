import 'dart:async';

import 'package:flutter/foundation.dart';

import '../net/messages.dart';
import '../net/transport.dart';
import 'matgo_game.dart';
import 'view_state.dart';
import 'wallet.dart';

/// 게임 상태와 통신을 이어 주는 층.
/// 방장: MatgoGame을 직접 들고 있고 참가자의 입력을 판정해서 각자 시점의 상태를 보낸다.
/// 참가자: 입력을 방장에게 보내고 받은 상태를 그대로 화면에 보여 준다.
class MatgoSession extends ChangeNotifier {
  final GameTransport t;
  final bool isHost;
  MatgoGame? _game;
  ViewState? view;
  int _seq = 0;
  int _gameId = 0;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _readyTimer;
  Timer? _walletTimer;
  final Set<int> _badSeats = {}; // 앱 버전이 다른 참가자 자리

  /// 상대 폰의 앱 버전이 달라서 게임을 진행할 수 없는 상태
  bool versionMismatch = false;

  /// 다른 자리 사람들이 보낸 지갑 사본 (자리 번호 -> 지갑). 상대 지갑 보기용.
  final Map<int, WalletSnapshot> wallets = {};

  /// 2인 대전에서 상대 지갑 (예전 코드 호환)
  WalletSnapshot? get oppWallet => wallets[1 - t.mySeat];

  int get players => t.players;
  int get mySeat => t.mySeat;

  // ------------------------------------------------------------ 지갑 공유

  Map<String, dynamic> _walletJson(int seat, {bool ask = false}) =>
      {'ask': ask, 'seat': seat, ...Wallet.i.snapshot().toJson()};

  void _sendMyWallet({bool ask = false}) {
    t.send(Msg.wallet, _walletJson(t.mySeat, ask: ask));
  }

  void _onWallet(Map<String, dynamic> m) {
    final from = m['_from'];
    // 방장은 참가자가 보낸 사본을 `_from` 으로 알고 참가자는 `seat` 로 안다
    final seat = isHost ? (from is int ? from : null) : m['seat'] as int?;
    if (seat == null || seat == t.mySeat) return;
    try {
      wallets[seat] = WalletSnapshot.fromJson(m);
      notifyListeners();
    } catch (_) {
      return;
    }
    if (isHost) {
      // 다른 참가자들에게 이어서 전달하고 물어본 사람에게는 모두의 지갑을 돌려준다
      for (var s = 1; s < t.players; s++) {
        if (s == seat) continue;
        t.sendTo(s, Msg.wallet, {...m, 'ask': false, 'seat': seat});
      }
      if (m['ask'] == true) {
        t.sendTo(seat, Msg.wallet, _walletJson(0));
        wallets.forEach((other, w) {
          if (other == seat) return;
          t.sendTo(seat, Msg.wallet, {'ask': false, 'seat': other, ...w.toJson()});
        });
      }
    } else if (m['ask'] == true) {
      _sendMyWallet();
    }
  }

  void _walletChanged() => _sendMyWallet();

  /// 내 지갑이 바뀔 때마다 보내고 다른 사람 지갑을 다 받을 때까지 다시 묻는다
  void _startWalletSync() {
    Wallet.i.addListener(_walletChanged);
    _sendMyWallet(ask: true);
    _walletTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (wallets.length >= t.players - 1) {
        _walletTimer?.cancel();
        return;
      }
      _sendMyWallet(ask: true);
    });
  }

  // ------------------------------------------------------------ 만들기

  MatgoSession.host(this.t) : isHost = true {
    _game = MatgoGame(players: t.players, first: 0);
    _gameId = DateTime.now().millisecondsSinceEpoch;
    _sub = t.messages.listen(_onMsg);
    _publish();
    _startWalletSync();
  }

  MatgoSession.guest(this.t) : isHost = false {
    _sub = t.messages.listen(_onMsg);
    t.send(Msg.ready, {'proto': kProtocol});
    // 방장이 아직 준비되기 전에 보낸 요청은 사라질 수 있어서 상태를 받을 때까지 다시 보낸다
    _readyTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (view != null || versionMismatch) {
        _readyTimer?.cancel();
        return;
      }
      t.send(Msg.ready, {'proto': kProtocol});
    });
    _startWalletSync();
  }

  // ---------------------------------------------------------------- 입력

  void play(int cardId, {bool shake = false}) {
    if (isHost) {
      if (_game!.playCard(0, cardId, shake: shake)) _publish();
    } else {
      t.send(Msg.playCard, {'cardId': cardId, 'shake': shake});
    }
  }

  void bomb(int month) {
    if (isHost) {
      if (_game!.playBomb(0, month)) _publish();
    } else {
      t.send(Msg.bomb, {'month': month});
    }
  }

  void flip() {
    if (isHost) {
      if (_game!.flipStock(0)) _publish();
    } else {
      t.send(Msg.flipStock);
    }
  }

  void choose(int cardId) {
    if (isHost) {
      if (_game!.chooseFloor(0, cardId)) _publish();
    } else {
      t.send(Msg.chooseFloor, {'cardId': cardId});
    }
  }

  void goStop(bool go) {
    if (isHost) {
      if (_game!.goStop(0, go)) _publish();
    } else {
      t.send(Msg.goStop, {'go': go});
    }
  }

  void newGame() {
    if (isHost) {
      _startNewGame();
    } else {
      t.send(Msg.newGame);
    }
  }

  // ---------------------------------------------------------------- 수신

  void _onMsg(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == Msg.wallet) {
      _onWallet(m);
      return;
    }
    if (isHost) {
      final from = m['_from'];
      if (from is! int) return;
      final g = _game!;
      switch (type) {
        case Msg.ready:
          if (m['proto'] != kProtocol) {
            _badSeats.add(from);
          } else {
            _badSeats.remove(from);
          }
          versionMismatch = _badSeats.isNotEmpty;
          notifyListeners();
          if (!_badSeats.contains(from)) _publishTo(from);
          break;
        case '_resumed':
          if (!_badSeats.contains(from)) _publishTo(from); // 재연결된 사람에게 현재 상태를 다시 보낸다
          t.sendTo(from, Msg.wallet, _walletJson(0, ask: true));
          break;
        case Msg.playCard:
          if (versionMismatch) break;
          if (g.playCard(from, m['cardId'] as int, shake: m['shake'] == true)) {
            _publish();
          }
          break;
        case Msg.bomb:
          if (g.playBomb(from, m['month'] as int)) _publish();
          break;
        case Msg.flipStock:
          if (g.flipStock(from)) _publish();
          break;
        case Msg.chooseFloor:
          if (g.chooseFloor(from, m['cardId'] as int)) _publish();
          break;
        case Msg.goStop:
          if (g.goStop(from, m['go'] == true)) _publish();
          break;
        case Msg.newGame:
          _startNewGame();
          break;
      }
    } else {
      switch (type) {
        case Msg.state:
          if (m['proto'] != kProtocol) {
            versionMismatch = true;
            notifyListeners();
            break;
          }
          try {
            view = ViewState.fromJson(m);
            _settle(view!);
            versionMismatch = false;
          } catch (_) {
            versionMismatch = true;
          }
          notifyListeners();
          break;
        case '_resumed':
          t.send(Msg.ready, {'proto': kProtocol});
          _sendMyWallet(ask: true);
          break;
      }
    }
  }

  // ---------------------------------------------------------------- 방장 전용

  void _startNewGame() {
    final g = _game!;
    if (g.phase != Phase.ended) return;
    _game = MatgoGame(players: g.n, first: g.nextFirst());
    _gameId = DateTime.now().millisecondsSinceEpoch;
    _publish();
  }

  void _publish() {
    final g = _game!;
    _seq++;
    view = ViewState.of(g, 0, _seq, gameId: _gameId);
    _settle(view!);
    notifyListeners();
    for (var seat = 1; seat < g.n; seat++) {
      _publishTo(seat, bump: false);
    }
  }

  void _publishTo(int seat, {bool bump = false}) {
    final g = _game!;
    if (bump) _seq++;
    t.sendTo(seat, Msg.state, ViewState.of(g, seat, _seq, gameId: _gameId).toJson());
  }

  /// 판이 끝나면 점수 이동 x 1억원을 정산한다. 나가리는 이동 없음.
  void _settle(ViewState v) {
    final r = v.result;
    if (v.phase != Phase.ended || r == null) return;
    final pay = r.payments.length > v.me
        ? r.payments[v.me]
        : (r.winner < 0 ? 0 : (r.winner == v.me ? r.points : -r.points));
    final others = v.others;
    Wallet.i.settle(
      v.gameId,
      pay * kWonPerPoint,
      result: r.winner < 0 ? 0 : (r.winner == v.me ? 1 : -1),
      myScore: v.scores[v.me],
      oppScore: v.scores[others[0]],
      oppScore2: others.length > 1 ? v.scores[others[1]] : -1,
      points: r.winner < 0 ? 0 : pay.abs(),
    );
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _walletTimer?.cancel();
    Wallet.i.removeListener(_walletChanged);
    _sub?.cancel();
    super.dispose();
  }
}
