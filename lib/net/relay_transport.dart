import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'messages.dart';
import 'relay.dart';
import 'transport.dart';

const String _root = 'matgo-hdlee/v1';
const String _codeChars = '0123456789';

String _rand(int n, String chars) {
  final r = Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

/// 방장 쪽에서 참가자 한 명의 연결 정보
class _Peer {
  _Peer(this.dev, this.seat) : joinedAt = DateTime.now(), lastRx = DateTime.now();
  final String dev;
  final int seat;
  final DateTime joinedAt;
  DateTime lastRx;
  bool alive = true;
  int lastN = 0; // 이 사람에게서 받은 마지막 메시지 번호
}

/// 방 코드로 만나는 인터넷 대전 통신 (방장 1명 + 참가자 1~2명).
/// 방장은 `$root/코드/h` 를 듣고 참가자는 `$root/코드/g/참가자ID` 를 듣는다.
/// 모든 메시지에 보낸 사람(_f)과 번호(_n)를 붙여서 남의 메시지와 중복 전달을 걸러낸다.
class RelayTransport implements GameTransport {
  RelayTransport(
    this._makeRelay, {
    this.pingEvery = const Duration(seconds: 3),
    this.deadAfter = const Duration(seconds: 12),
    this.helloEvery = const Duration(seconds: 2),
    this.joinTimeout = const Duration(seconds: 12),
    this.reconnectWindow = kReconnectWindow,
  });

  final Relay Function() _makeRelay;
  final Duration pingEvery;
  final Duration deadAfter;
  final Duration helloEvery;
  final Duration joinTimeout;
  final Duration reconnectWindow;

  final _stateC = StreamController<LinkState>.broadcast();
  final _roomsC = StreamController<List<Room>>.broadcast();
  final _msgC = StreamController<Map<String, dynamic>>.broadcast();
  final _logC = StreamController<String>.broadcast();

  final String _devId = _rand(10, 'abcdefghijklmnopqrstuvwxyz0123456789');
  Relay? _relay;
  StreamSubscription<RelayMsg>? _inSub;
  StreamSubscription<bool>? _onlineSub;

  LinkState _state = LinkState.idle;
  bool _isHost = false;
  bool _closed = false;
  bool _everConnected = false; // 참가자: 방장과 한 번이라도 연결됨
  bool _everFull = false; // 방장: 모든 자리가 한 번이라도 찼음
  int _players = 2;
  int _mySeat = 0;
  String _code = '';
  int _n = 0;
  int _hostLastN = 0; // 참가자: 방장에게서 받은 마지막 메시지 번호
  DateTime _lastRx = DateTime.now(); // 참가자: 방장에게서 마지막으로 받은 시각
  DateTime _joinStart = DateTime.now();
  final Map<String, _Peer> _peers = {};
  Timer? _pingTimer;
  Timer? _helloTimer;
  Timer? _reconnectTimer;

  @override
  Stream<LinkState> get state => _stateC.stream;
  @override
  Stream<List<Room>> get rooms => _roomsC.stream;
  @override
  Stream<Map<String, dynamic>> get messages => _msgC.stream;
  @override
  Stream<String> get logs => _logC.stream;
  @override
  LinkState get current => _state;
  @override
  bool get isHost => _isHost;
  @override
  String? get roomCode => _code.isEmpty ? null : _code;
  @override
  int get players => _players;
  @override
  int get mySeat => _mySeat;
  @override
  int get joined => _peers.length;

  String get _base => '$_root/$_code';
  String get _hostTopic => '$_base/h';
  String _guestTopic(String dev) => '$_base/g/$dev';

  // ---------------------------------------------------------------- 공개 API

  @override
  Future<void> host({int players = 2}) async {
    await _reset();
    _isHost = true;
    _players = players;
    _mySeat = 0;
    _code = _rand(2, _codeChars); // 두 자리 숫자
    _log('방 코드: $_code (${players}명)');
    if (!await _openRelay()) return;
    _relay!.subscribe(_hostTopic);
    _set(LinkState.advertising);
  }

  /// 인터넷 대전은 방 목록이 없고 코드로만 들어간다.
  @override
  Future<void> startSearch() async {
    await _reset();
    _isHost = false;
    _set(LinkState.discovering);
  }

  /// [room] 의 endpointId 가 방 코드
  @override
  Future<void> join(Room room) async {
    await _reset();
    _isHost = false;
    _code = room.endpointId.trim().toUpperCase();
    _set(LinkState.connecting);
    if (!await _openRelay()) return;
    _relay!.subscribe(_guestTopic(_devId));
    _joinStart = DateTime.now();
    _sendHello();
    _helloTimer = Timer.periodic(helloEvery, (_) {
      if (_state != LinkState.connecting) {
        _helloTimer?.cancel();
        return;
      }
      if (DateTime.now().difference(_joinStart) > joinTimeout) {
        _fail('방을 찾을 수 없어. 코드를 확인해줘');
        return;
      }
      _sendHello();
    });
  }

  @override
  Future<bool> send(String type, [Map<String, dynamic> data = const {}]) async {
    if (_isHost) {
      var any = false;
      for (final p in _peers.values) {
        if (p.alive && _toPeer(p, type, data)) any = true;
      }
      return any;
    }
    if (_state != LinkState.connected) return false;
    return _toHost(type, data);
  }

  @override
  Future<bool> sendTo(int seat, String type,
      [Map<String, dynamic> data = const {}]) async {
    if (!_isHost) return send(type, data);
    for (final p in _peers.values) {
      if (p.seat == seat && p.alive) return _toPeer(p, type, data);
    }
    return false;
  }

  @override
  Future<void> debugDrop() async {}

  @override
  Future<void> close() async {
    _closed = true;
    _byeAll('leave');
    await _teardown();
    _set(LinkState.idle);
  }

  // ------------------------------------------------------------ 서버 연결

  Future<bool> _openRelay() async {
    final r = _makeRelay();
    _relay = r;
    _inSub = r.incoming.listen(_onRelay);
    _onlineSub = r.online.listen((on) {
      _log(on ? '인터넷 서버 연결됨' : '인터넷 서버 연결이 끊김');
    });
    final ok = await r.connect();
    if (!ok) {
      await _fail('인터넷 서버에 연결할 수 없어');
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------- 보내기

  String _encode(String type, Map<String, dynamic> data) =>
      jsonEncode({'type': type, ...data, '_n': ++_n, '_f': _devId});

  bool _toPeer(_Peer p, String type, Map<String, dynamic> data) {
    final r = _relay;
    if (r == null) return false;
    r.publish(_guestTopic(p.dev), _encode(type, data));
    return true;
  }

  bool _toHost(String type, Map<String, dynamic> data) {
    final r = _relay;
    if (r == null) return false;
    r.publish(_hostTopic, _encode(type, data));
    return true;
  }

  void _sendHello() {
    _relay?.publish(_hostTopic, _encode(Msg.hello, {'deviceId': _devId}));
  }

  void _byeAll(String reason) {
    if (_isHost) {
      for (final p in _peers.values) {
        _toPeer(p, Msg.bye, {'reason': reason});
      }
    } else if (_state == LinkState.connected) {
      _toHost(Msg.bye, {'reason': reason});
    }
  }

  // ------------------------------------------------------------- 받기

  void _onRelay(RelayMsg r) {
    if (_closed) return;
    final Map<String, dynamic> m;
    try {
      final v = jsonDecode(r.payload);
      if (v is! Map<String, dynamic>) return;
      m = v;
    } catch (_) {
      return;
    }
    final from = m['_f'];
    final type = m['type'];
    final n = m['_n'];
    if (from is! String || type is! String || from == _devId) return;

    if (_isHost) {
      if (r.topic != _hostTopic) return;
      if (type == Msg.hello) {
        _onHello(from);
        return;
      }
      final peer = _peers[from];
      if (peer == null) return;
      if (n is int) {
        if (n <= peer.lastN) return; // 서버가 같은 메시지를 두 번 준 경우
        peer.lastN = n;
      }
      peer.lastRx = DateTime.now();
      if (!peer.alive) {
        peer.alive = true;
        _log('${peer.seat}번 자리와 다시 연결됐어');
        _refreshHostState();
        _msgC.add({'type': '_resumed', '_from': peer.seat});
      }
      switch (type) {
        case Msg.ping:
          break;
        case Msg.bye:
          _onPeerBye(peer);
          break;
        default:
          _msgC.add({...m, '_from': peer.seat});
      }
      return;
    }

    // 참가자
    if (r.topic != _guestTopic(_devId)) return;
    if (n is int) {
      if (n <= _hostLastN) return;
      _hostLastN = n;
    }
    _lastRx = DateTime.now();
    if (_state == LinkState.reconnecting) {
      _reconnectTimer?.cancel();
      _set(LinkState.connected);
      _log('방장과 다시 연결됐어');
      _msgC.add({'type': '_resumed'});
    }
    switch (type) {
      case Msg.welcome:
        _onWelcome(m);
        break;
      case Msg.ping:
        break;
      case Msg.bye:
        _fail(m['reason'] == 'room_full' ? '이미 사람이 다 찬 방이야' : '방장이 나갔어');
        break;
      default:
        _msgC.add({...m, '_from': 0});
    }
  }

  // ---------------------------------------------------------- 방장 처리

  int _freeSeat() {
    for (var s = 1; s < _players; s++) {
      if (!_peers.values.any((p) => p.seat == s)) return s;
    }
    return -1;
  }

  void _onHello(String dev) {
    var peer = _peers[dev];
    var resumed = false;
    var dup = false;
    if (peer == null) {
      final seat = _freeSeat();
      if (seat < 0) {
        // 자리가 다 찬 방에 낯선 기기가 들어옴
        _relay?.publish(
          _guestTopic(dev),
          _encode(Msg.bye, {'reason': 'room_full'}),
        );
        return;
      }
      peer = _Peer(dev, seat);
      _peers[dev] = peer;
      _log('${peer.seat}번 자리에 참가자가 들어왔어 (${_peers.length}/${_players - 1})');
    } else {
      dup = DateTime.now().difference(peer.joinedAt) < const Duration(seconds: 6);
      resumed = !dup;
      peer.alive = true;
      peer.lastRx = DateTime.now();
    }
    _toPeer(peer, Msg.welcome, {
      'resumed': resumed,
      'seat': peer.seat,
      'players': _players,
    });
    _refreshHostState();
    _startPing();
    if (resumed) _msgC.add({'type': '_resumed', '_from': peer.seat});
  }

  void _onPeerBye(_Peer peer) {
    if (_everFull) {
      _fail('${peer.seat}번 자리 사람이 나갔어');
      return;
    }
    // 아직 게임 시작 전이면 자리만 비워 준다
    _peers.remove(peer.dev);
    _log('${peer.seat}번 자리 사람이 나갔어');
    _refreshHostState();
  }

  /// 방장의 상태를 참가자들 연결 상황에 맞춰 정한다
  void _refreshHostState() {
    if (_closed || _state == LinkState.failed) return;
    if (_peers.length < _players - 1) {
      _set(LinkState.advertising); // 사람이 더 들어오길 기다림 (인원 표시를 위해 다시 알림)
      return;
    }
    _everFull = true;
    if (_peers.values.every((p) => p.alive)) {
      _reconnectTimer?.cancel();
      if (_state != LinkState.connected) _set(LinkState.connected);
    } else if (_state != LinkState.reconnecting) {
      _set(LinkState.reconnecting);
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectWindow, () => _fail('재연결 시간 초과'));
    }
  }

  void _onWelcome(Map<String, dynamic> m) {
    _everConnected = true;
    _mySeat = (m['seat'] as int?) ?? 1;
    _players = (m['players'] as int?) ?? 2;
    _helloTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_state != LinkState.connected) _set(LinkState.connected);
    _startPing();
    if (m['resumed'] == true) _msgC.add({'type': '_resumed'});
  }

  // ------------------------------------------------------- 끊김과 재연결

  void _startPing() {
    if (_pingTimer?.isActive == true) return;
    _lastRx = DateTime.now();
    _pingTimer = Timer.periodic(pingEvery, (_) {
      if (_closed) return;
      if (_isHost) {
        var changed = false;
        for (final p in _peers.values) {
          _toPeer(p, Msg.ping, const {});
          if (p.alive && DateTime.now().difference(p.lastRx) > deadAfter) {
            p.alive = false;
            changed = true;
            _log('${p.seat}번 자리 응답 없음');
          }
        }
        if (changed) _refreshHostState();
        return;
      }
      if (_state != LinkState.connected && _state != LinkState.reconnecting) {
        return;
      }
      _toHost(Msg.ping, const {});
      if (_state == LinkState.connected &&
          DateTime.now().difference(_lastRx) > deadAfter) {
        _log('방장 응답 없음 - ${reconnectWindow.inSeconds}초 동안 기다릴게');
        _set(LinkState.reconnecting);
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(reconnectWindow, () => _fail('재연결 시간 초과'));
      }
    });
  }

  Future<void> _fail(String why) async {
    if (_closed) return;
    _log('연결 종료: $why');
    if (_isHost) _byeAll('fail');
    await _teardown();
    _set(LinkState.failed);
  }

  Future<void> _teardown() async {
    _pingTimer?.cancel();
    _helloTimer?.cancel();
    _reconnectTimer?.cancel();
    await _inSub?.cancel();
    await _onlineSub?.cancel();
    _inSub = null;
    _onlineSub = null;
    final r = _relay;
    _relay = null;
    try {
      await r?.close();
    } catch (_) {}
  }

  Future<void> _reset() async {
    await _teardown();
    _closed = false;
    _everConnected = false;
    _everFull = false;
    _peers.clear();
    _code = '';
    _n = 0;
    _hostLastN = 0;
    _mySeat = 0;
    _players = 2;
  }

  // ------------------------------------------------------------------ 기타

  void _set(LinkState s) {
    _state = s;
    _stateC.add(s);
  }

  void _log(String m) {
    _logC.add('[인터넷 ${_isHost ? '방장' : '참가자'}] $m');
  }
}
