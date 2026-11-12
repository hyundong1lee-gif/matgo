import 'dart:async';

import 'package:flutter/foundation.dart';

import '../net/messages.dart';
import '../net/transport.dart';
import 'matgo_game.dart';
import 'view_state.dart';

/// 게임 상태와 통신을 이어 주는 층.
/// 방장: MatgoGame을 직접 들고 있고 참가자의 입력을 판정해서 각자 시점의 상태를 보낸다.
/// 참가자: 입력을 방장에게 보내고 받은 상태를 그대로 화면에 보여 준다.
class MatgoSession extends ChangeNotifier {
  final GameTransport t;
  final bool isHost;
  MatgoGame? _game;
  ViewState? view;
  int _seq = 0;
  StreamSubscription<Map<String, dynamic>>? _sub;

  MatgoSession.host(this.t) : isHost = true {
    _game = MatgoGame(first: 0);
    _sub = t.messages.listen(_onMsg);
    _publish();
  }

  MatgoSession.guest(this.t) : isHost = false {
    _sub = t.messages.listen(_onMsg);
    t.send(Msg.ready);
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
    if (isHost) {
      final g = _game!;
      switch (type) {
        case Msg.ready:
        case '_resumed':
          _publish(); // 재연결되면 현재 상태를 그대로 다시 보낸다
          break;
        case Msg.playCard:
          if (g.playCard(1, m['cardId'] as int, shake: m['shake'] == true)) {
            _publish();
          }
          break;
        case Msg.bomb:
          if (g.playBomb(1, m['month'] as int)) _publish();
          break;
        case Msg.flipStock:
          if (g.flipStock(1)) _publish();
          break;
        case Msg.chooseFloor:
          if (g.chooseFloor(1, m['cardId'] as int)) _publish();
          break;
        case Msg.goStop:
          if (g.goStop(1, m['go'] == true)) _publish();
          break;
        case Msg.newGame:
          _startNewGame();
          break;
      }
    } else {
      switch (type) {
        case Msg.state:
          view = ViewState.fromJson(m);
          notifyListeners();
          break;
        case '_resumed':
          t.send(Msg.ready);
          break;
      }
    }
  }

  // ---------------------------------------------------------------- 방장 전용

  void _startNewGame() {
    final g = _game!;
    if (g.phase != Phase.ended) return;
    _game = MatgoGame(first: g.nextFirst());
    _publish();
  }

  void _publish() {
    final g = _game!;
    _seq++;
    view = ViewState.of(g, 0, _seq);
    notifyListeners();
    t.send(Msg.state, ViewState.of(g, 1, _seq).toJson());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
