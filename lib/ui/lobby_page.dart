import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../game/session.dart';
import '../game/wallet.dart';
import '../net/messages.dart';
import '../net/nearby_transport.dart';
import '../net/permissions.dart';
import '../net/transport.dart';
import 'game_page.dart';
import 'stats_page.dart';
import 'wallet_panel.dart';

/// 시작 화면: 방 만들기 / 방 찾기 / 연결 대기
class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key, required this.t});

  final GameTransport t;

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  final List<StreamSubscription<dynamic>> subs = [];
  final List<String> logs = [];
  LinkState state = LinkState.idle;
  List<Room> rooms = [];
  PermIssue issue = PermIssue.none;
  bool inGame = false;

  @override
  void initState() {
    super.initState();
    state = widget.t.current;
    subs.add(widget.t.state.listen(_onState));
    subs.add(widget.t.rooms.listen((r) {
      if (mounted) setState(() => rooms = r);
    }));
    subs.add(widget.t.logs.listen((l) {
      if (!mounted) return;
      final now = DateTime.now().toString().substring(11, 19);
      setState(() {
        logs.insert(0, '$now $l');
        if (logs.length > 6) logs.removeLast();
      });
    }));
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _onState(LinkState s) {
    if (!mounted) return;
    setState(() => state = s);
    if (s == LinkState.connected && !inGame) {
      _enterGame();
    }
  }

  Future<void> _enterGame() async {
    inGame = true;
    final t = widget.t;
    final session = t.isHost ? MatgoSession.host(t) : MatgoSession.guest(t);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GamePage(session: session, t: t),
      ),
    );
    session.dispose();
    await t.close();
    if (mounted) setState(() => inGame = false);
  }

  Future<void> _start(bool host) async {
    final r = await checkNearbyPermissions();
    if (!mounted) return;
    setState(() => issue = r);
    if (r != PermIssue.none) return;
    if (host) {
      await widget.t.host();
    } else {
      await widget.t.startSearch();
    }
  }

  String get _stateText {
    if (state == LinkState.idle) return '대기 중';
    if (state == LinkState.advertising) return '방이 열렸어. 친구가 들어오길 기다리는 중...';
    if (state == LinkState.discovering) return '방을 찾는 중...';
    if (state == LinkState.connecting) return '연결 중...';
    if (state == LinkState.connected) return '연결됨';
    if (state == LinkState.reconnecting) return '재연결 중...';
    return '연결이 끊겼어. 다시 시작해줘.';
  }

  @override
  Widget build(BuildContext context) {
    final canStart = state == LinkState.idle || state == LinkState.failed;
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '블루투스 맞고',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '인터넷 없이 가까운 폰끼리',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '앱 버전 $kAppVersion',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ListenableBuilder(
                      listenable: Wallet.i,
                      builder: (context, _) => TextButton(
                        onPressed: () => showWallet(context),
                        child: Text(
                          '내 지갑 ${won(Wallet.i.money)}'
                          '${Wallet.i.debt > 0 ? ' · 빚 ${won(Wallet.i.debt)}' : ''}',
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StatsPage(),
                        ),
                      ),
                      child: const Text(
                        '전적 보기',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      onPressed: canStart ? () => _start(true) : null,
                      child: const Text('방 만들기'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: canStart ? () => _start(false) : null,
                      child: const Text('방 찾기'),
                    ),
                    if (!canStart) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: widget.t.close,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('취소'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _stateText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (issue != PermIssue.none) ...[
                      const SizedBox(height: 8),
                      Text(
                        permIssueText(issue),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.yellowAccent),
                      ),
                      TextButton(
                        onPressed: openAppSettings,
                        child: const Text('설정 열기'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state == LinkState.discovering ? '찾은 방' : '안내',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (state == LinkState.discovering) ...[
                      if (rooms.isEmpty)
                        const Text('아직 없어. 친구가 방을 만들었는지 확인해줘.',
                            style: TextStyle(color: Colors.white70)),
                      for (final r in rooms)
                        Card(
                          child: ListTile(
                            dense: true,
                            title: Text(r.name),
                            trailing: const Icon(Icons.login),
                            onTap: () => widget.t.join(r),
                          ),
                        ),
                    ] else
                      const Text(
                        '1. 한 명이 "방 만들기"를 누른다\n'
                        '2. 다른 한 명이 "방 찾기"를 누르고 방을 고른다\n'
                        '3. 두 폰 모두 블루투스와 위치(GPS)가 켜져 있어야 해',
                        style: TextStyle(color: Colors.white70),
                      ),
                    const Spacer(),
                    for (final l in logs)
                      Text(
                        l,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
