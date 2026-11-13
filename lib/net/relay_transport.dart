import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'messages.dart';
import 'relay.dart';
import 'transport.dart';

const String _root = 'matgo-hdlee/v1';
const String _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _rand(int n, String chars) {
  final r = Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

/// 방 코드로 만나는 인터넷 대전 통신.
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
  bool _everConnected = false;
  String _code = '';
  String? _peerDev;
  int _n = 0;
  int _lastPeerN = 0;
  DateTime _lastRx = DateTime.now();
  DateTime _joinStart = DateTime.now();
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

  String get _base => '$_root/$_code';
  String get _hostTopic => '$_base/h';
  String _guestTopic(String dev) => '$_base/g/$dev';

  // ---------------------------------------------------------------- 공개 API

  @override
  Future<void> host() async {
    await _reset();
    _isHost = true;
    _code = _rand(6, _codeChars);
    _log('방 코드: $_code');
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
    if (_state != LinkState.connected) return false;
    return _pub(type, data);
  }

  @override
  Future<void> debugDrop() async {}

  @override
  Future<void> close() async {
    _closed = true;
    if (_state == LinkState.connected) _pub(Msg.bye, {'reason': 'leave'});
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

  bool _pub(String type, Map<String, dynamic> data) {
    final r = _relay;
    if (r == null) return false;
    final String topic;
    if (_isHost) {
      final dev = _peerDev;
      if (dev == null) return false;
      topic = _guestTopic(dev);
    } else {
      topic = _hostTopic;
    }
    r.publish(topic, _encode(type, data));
    return true;
  }

  String _encode(String type, Map<String, dynamic> data) =>
      jsonEncode({'type': type, ...data, '_n': ++_n, '_f': _devId});

  void _sendHello() {
    _relay?.publish(_hostTopic, _encode(Msg.hello, {'deviceId': _devId}));
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
        _onHello(from, n is int ? n : 0);
        return;
      }
      if (from != _peerDev) return;
    } else {
      if (r.topic != _guestTopic(_devId)) return;
    }

    if (n is int) {
      if (n <= _lastPeerN) return; // 서버가 같은 메시지를 두 번 준 경우
      _lastPeerN = n;
    }
    _lastRx = DateTime.now();

    if (_state == LinkState.reconnecting) {
      _reconnectTimer?.cancel();
      _set(LinkState.connected);
      _log('상대와 다시 연결됐어');
      _msgC.add({'type': '_resumed'});
    }

    switch (type) {
      case Msg.welcome:
        _onWelcome(m);
        break;
      case Msg.ping:
        break;
      case Msg.bye:
        _fail(m['reason'] == 'room_full' ? '이미 다른 상대가 있는 방이야' : '상대가 나갔어');
        break;
      default:
        _msgC.add(m);
    }
  }

  void _onHello(String dev, int n) {
    if (_everConnected && dev != _peerDev) {
      // 이미 정해진 상대가 있는 방에 낯선 기기가 들어옴
      _relay?.publish(
        _guestTopic(dev),
        _encode(Msg.bye, {'reason': 'room_full'}),
      );
      return;
    }
    final resumed = _everConnected;
    _peerDev = dev;
    _everConnected = true;
    if (n > _lastPeerN) _lastPeerN = n;
    _lastRx = DateTime.now();
    _reconnectTimer?.cancel();
    _pub(Msg.welcome, {'resumed': resumed});
    if (_state != LinkState.connected) _set(LinkState.connected);
    _startPing();
    if (resumed) _msgC.add({'type': '_resumed'});
  }

  void _onWelcome(Map<String, dynamic> m) {
    if (_isHost) return;
    final first = !_everConnected;
    _everConnected = true;
    _helloTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_state != LinkState.connected) _set(LinkState.connected);
    _startPing();
    if (!first || m['resumed'] == true) _msgC.add({'type': '_resumed'});
  }

  // ------------------------------------------------------- 끊김과 재연결

  void _startPing() {
    _pingTimer?.cancel();
    _lastRx = DateTime.now();
    _pingTimer = Timer.periodic(pingEvery, (_) {
      if (_closed) return;
      if (_state != LinkState.connected && _state != LinkState.reconnecting) {
        return;
      }
      _pub(Msg.ping, const {});
      if (_state == LinkState.connected &&
          DateTime.now().difference(_lastRx) > deadAfter) {
        _log('상대 응답 없음 - ${reconnectWindow.inSeconds}초 동안 기다릴게');
        _set(LinkState.reconnecting);
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(reconnectWindow, () => _fail('재연결 시간 초과'));
      }
    });
  }

  Future<void> _fail(String why) async {
    if (_closed) return;
    _log('연결 종료: $why');
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
    _peerDev = null;
    _code = '';
    _n = 0;
    _lastPeerN = 0;
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
