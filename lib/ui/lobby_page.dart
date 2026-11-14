import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../game/session.dart';
import '../game/wallet.dart';
import '../net/messages.dart';
import '../net/nearby_transport.dart';
import '../net/mqtt_relay.dart';
import '../net/permissions.dart';
import '../net/relay_transport.dart';
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

  late GameTransport _t;

  @override
  void initState() {
    super.initState();
    _t = widget.t;
    _listen();
  }

  /// 지금 쓰는 통신(근처 연결 또는 인터넷)의 상태를 듣는다
  void _listen() {
    for (final s in subs) {
      s.cancel();
    }
    subs.clear();
    state = _t.current;
    rooms = [];
    subs.add(_t.state.listen(_onState));
    subs.add(_t.rooms.listen((r) {
      if (mounted) setState(() => rooms = r);
    }));
    subs.add(_t.logs.listen((l) {
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

  /// 근처 연결(블루투스)로 되돌린다
  void _useNearby() {
    if (_t == widget.t) return;
    _t = widget.t;
    _listen();
    if (mounted) setState(() {});
  }

  Future<void> _enterGame() async {
    inGame = true;
    final t = _t;
    final session = t.isHost ? MatgoSession.host(t) : MatgoSession.guest(t);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GamePage(session: session, t: t),
      ),
    );
    session.dispose();
    await t.close();
    _useNearby();
    if (mounted) setState(() => inGame = false);
  }

  Future<void> _cancel() async {
    await _t.close();
    _useNearby();
  }

  /// 게임에서 쓸 이름을 입력받는다 (취소하면 false)
  Future<bool> _editName() async {
    final ctl = TextEditingController(text: Wallet.i.name);
    String? err;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('내 이름'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 8,
            decoration: InputDecoration(
              hintText: '게임에서 보일 이름 (최대 8글자)',
              errorText: err,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (err != null) setS(() => err = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final t = ctl.text.trim();
                if (t.isEmpty) {
                  setS(() => err = '이름을 입력해줘');
                  return;
                }
                Navigator.of(ctx).pop(t);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (r == null) return false;
    Wallet.i.setName(r);
    return true;
  }

  /// 이름이 없으면 먼저 정하게 한다
  Future<bool> _ensureName() async {
    if (Wallet.i.name.isNotEmpty) return true;
    final ok = await _editName();
    return ok && mounted;
  }

  /// 방 만들 때 몇 명이 할지 고른다 (취소하면 null)
  Future<int?> _pickPlayers() {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('몇 명이서 할까?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(2),
            child: const Text('2명 (1:1)', style: TextStyle(fontSize: 16)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(3),
            child: const Text('3명', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _startNet(bool host, [String code = '', int players = 2]) async {
    final nt = RelayTransport(() => MqttRelay());
    _t = nt;
    _listen();
    setState(() => issue = PermIssue.none);
    if (host) {
      await nt.host(players: players);
    } else {
      await nt.join(Room(code, code));
    }
  }

  Future<void> _netDialog() async {
    if (!await _ensureName()) return;
    final ctl = TextEditingController();
    final r = await showDialog<(bool, String, int)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('인터넷 대전'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop((true, '', 2)),
                child: const Text('2명 방 만들기 (코드 받기)'),
              ),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop((true, '', 3)),
                child: const Text('3명 방 만들기 (코드 받기)'),
              ),
              const Divider(height: 24),
              TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 2,
                decoration: const InputDecoration(
                  labelText: '친구가 알려준 방 코드 (두 자리 숫자)',
                  border: OutlineInputBorder(),
                ),
              ),
              FilledButton.tonal(
                onPressed: () {
                  final c = ctl.text.trim().toUpperCase();
                  if (c.length == 2) Navigator.of(ctx).pop((false, c, 2));
                },
                child: const Text('코드로 입장'),
              ),
            ],
          ),
        ),
      ),
    );
    if (r == null || !mounted) return;
    await _startNet(r.$1, r.$2, r.$3);
  }

  Future<void> _start(bool host) async {
    if (!await _ensureName()) return;
    _useNearby();
    int players = 2;
    if (host) {
      final n = await _pickPlayers();
      if (n == null || !mounted) return;
      players = n;
    }
    final r = await checkNearbyPermissions();
    if (!mounted) return;
    setState(() => issue = r);
    if (r != PermIssue.none) return;
    if (host) {
      await _t.host(players: players);
    } else {
      await _t.startSearch();
    }
  }

  String get _stateText {
    if (state == LinkState.idle) return '대기 중';
    if (state == LinkState.advertising) {
      final cnt = '(${_t.joined + 1}/${_t.players}명)';
      return _t.roomCode != null
          ? '방이 열렸어. 코드를 친구에게 알려줘 $cnt'
          : '방이 열렸어. 친구가 들어오길 기다리는 중... $cnt';
    }
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
                      '2~3명 · 인터넷 없이 가까운 폰끼리',
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
                    ListenableBuilder(
                      listenable: Wallet.i,
                      builder: (context, _) => TextButton(
                        onPressed: _editName,
                        child: Text(
                          Wallet.i.name.isEmpty
                              ? '이름 정하기'
                              : '이름: ${Wallet.i.name} (바꾸기)',
                          style: const TextStyle(color: Colors.white),
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
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: canStart ? _netDialog : null,
                      child: const Text('인터넷으로 하기'),
                    ),
                    if (!canStart) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _cancel,
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
                            title: Text(
                              '${r.name.replaceFirst(RegExp(r'-\d$'), '')}'
                              ' · ${NearbyTransport.playersOf(r.name)}명',
                            ),
                            trailing: const Icon(Icons.login),
                            onTap: () => _t.join(r),
                          ),
                        ),
                    ] else if (_t.roomCode != null) ...[
                      if (state == LinkState.advertising)
                        InkWell(
                          onTap: () => Clipboard.setData(
                            ClipboardData(text: _t.roomCode!),
                          ),
                          child: Center(
                            child: Text(
                              _t.roomCode!,
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 10,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        '이 코드를 친구에게 알려줘 (누르면 복사)\n친구는 "인터넷으로 하기"에서 코드로 입장하면 돼\n${_t.players}명 방 · 지금 ${_t.joined + 1}명',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ] else
                      const Text(
                        '[근처 연결]\n'
                        '1. 한 명이 "방 만들기"를 누른다\n'
                        '2. 나머지 사람이 "방 찾기"를 누르고 방을 고른다\n'
                        '3. 모든 폰에 블루투스와 위치(GPS)가 켜져 있어야 해\n\n'
                        '[인터넷] 멀리 있는 친구와는 "인터넷으로 하기"를 눌러 방 코드로 만나',
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
